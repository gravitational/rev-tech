# control-plane/eks/4-plugins/main.tf
#
# Deploys the Teleport Slack access request plugin into the EKS cluster.
# Depends on: 1-cluster (remote state), 2-teleport (cluster running), 3-rbac (roles exist).
#
# What gets created:
#   - Teleport role:  slack-access-plugin  (read + approve/deny access requests)
#   - Teleport user:  slack-plugin-service (service account for the plugin)
#   - Kubernetes namespace: teleport-plugins
#   - Kubernetes secret:    Slack credentials (token + signing secret)
#   - Helm release:         teleport-plugin-slack
#
# Bootstrap (one-time, after first apply):
#   1. Generate an identity file for the plugin service user:
#        tctl auth sign --format=file --user=slack-plugin-service \
#          --out=plugin-identity --ttl=8760h
#   2. Store it as a Kubernetes secret:
#        kubectl create secret generic teleport-plugin-slack-identity \
#          --from-file=auth_id=plugin-identity \
#          -n teleport-plugins
#   3. Restart the plugin to pick up the secret:
#        kubectl rollout restart deployment/teleport-plugin-slack -n teleport-plugins
#
# After bootstrap, re-runs of terraform apply are idempotent (secret persists).

# ---------------------------------------------------------------------------
# Teleport RBAC: plugin service role + user
# (using kubectl_manifest to match the 3-rbac layer pattern)
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "role_slack_access_plugin" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "slack-access-plugin"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      allow = {
        rules = [
          {
            resources = ["access_request"]
            verbs     = ["list", "read", "update"]
          },
          {
            resources = ["user"]
            verbs     = ["list", "read"]
          },
        ]
      }
    }
  })
}

resource "kubectl_manifest" "user_slack_plugin_service" {
  depends_on = [kubectl_manifest.role_slack_access_plugin]
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportUser"
    metadata = {
      name      = "slack-plugin-service"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      roles = ["slack-access-plugin"]
    }
  })
}

# ---------------------------------------------------------------------------
# Kubernetes: plugin namespace + Slack credentials secret
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "plugins" {
  metadata {
    name = var.plugin_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret" "slack_credentials" {
  metadata {
    name      = "teleport-plugin-slack-credentials"
    namespace = kubernetes_namespace.plugins.metadata[0].name
  }

  data = {
    token          = var.slack_bot_token
    signing_secret = var.slack_signing_secret
  }

  type = "Opaque"
}

# ---------------------------------------------------------------------------
# Helm: teleport-plugin-slack
#
# Authentication: the plugin reads an identity file from the
# "teleport-plugin-slack-identity" Kubernetes secret (key: auth_id).
# Create this secret via the bootstrap steps documented above.
# ---------------------------------------------------------------------------

locals {
  chart_version = var.plugin_chart_version != "" ? var.plugin_chart_version : null

  # All requestable roles notify the configured channel.
  role_to_recipients = {
    "prod-access"          = [var.slack_channel_id]
    "prod-readonly-access" = [var.slack_channel_id]
    "platform-dev-access"  = [var.slack_channel_id]
    "*"                    = [var.slack_channel_id]
  }
}

resource "helm_release" "teleport_plugin_slack" {
  depends_on = [
    kubectl_manifest.user_slack_plugin_service,
    kubernetes_secret.slack_credentials,
  ]

  name       = "teleport-plugin-slack"
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-plugin-slack"
  namespace  = kubernetes_namespace.plugins.metadata[0].name
  version    = local.chart_version

  # Wait for the deployment to be ready. The plugin pod will stay in
  # CrashLoopBackOff until the identity secret is created (bootstrap step 2).
  wait    = false
  timeout = 120

  values = [yamlencode({
    teleport = {
      address = "${var.proxy_address}:443"
      # Identity file secret — created in the bootstrap step above.
      identitySecretName = "teleport-plugin-slack-identity"
      identitySecretPath = "auth_id"
    }

    slack = {
      token = var.slack_bot_token
    }

    # Role → Slack channel mapping.
    # Keys are Teleport role names that users request.
    # Values are Slack channel IDs that receive the approval notification.
    roleToRecipients = local.role_to_recipients

    log = {
      output   = "stdout"
      severity = "INFO"
    }
  })]
}
