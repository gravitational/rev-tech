# control-plane/eks/4-plugins/main.tf
#
# Deploys the Teleport Slack access request plugin into the EKS cluster.
# Depends on: 1-cluster (remote state), 2-teleport (cluster running), 3-rbac (roles exist).
#
# What gets created:
#   Teleport resources (via operator CRDs):
#     - TeleportRoleV7:         slack-access-plugin
#     - TeleportBot:            slack-plugin (Machine ID)
#     - TeleportProvisionToken: tbot-slack-plugin (kubernetes join — no stored secrets)
#
#   Kubernetes resources:
#     - Namespace:    teleport-plugins
#     - Secret:       teleport-plugin-slack-credentials (Slack bot token)
#     - Helm release: teleport-plugin-slack (includes tbot sidecar for auto-renewing certs)
#
# No manual bootstrap required. The chart's built-in tbot handles credential
# issuance and renewal via the kubernetes join method.

##################################################################################
# TELEPORT RBAC: plugin role + Machine ID bot
##################################################################################

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
          { resources = ["access_request"], verbs = ["list", "read", "update"] },
          { resources = ["user"], verbs = ["list", "read"] },
          { resources = ["role"], verbs = ["list", "read"] },
        ]
      }
    }
  })
}

# TeleportBot replaces the static TeleportUser. The operator creates the bot
# in Teleport. The plugin authenticates as this bot via tbot (kubernetes join).
resource "kubectl_manifest" "bot_slack_plugin" {
  depends_on = [kubectl_manifest.role_slack_access_plugin]
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportBotV1"
    metadata = {
      name      = "slack-plugin"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      roles = ["slack-access-plugin"]
    }
  })
}

# Kubernetes join token: the tbot sidecar (running inside the plugin pod) presents
# its pod ServiceAccount JWT to Teleport to authenticate — no stored tokens needed.
# The tbot SA is named after the Helm release + "-tbot": teleport-plugin-slack-tbot.
resource "kubectl_manifest" "provision_token_tbot_slack" {
  depends_on = [kubectl_manifest.bot_slack_plugin]
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportProvisionToken"
    metadata = {
      name      = "tbot-slack-plugin"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      roles       = ["Bot"]
      bot_name    = "slack-plugin"
      join_method = "kubernetes"
      kubernetes = {
        allow = [
          {
            service_account = "${var.plugin_namespace}:teleport-plugin-slack-tbot"
          }
        ]
      }
    }
  })
}

##################################################################################
# KUBERNETES: plugin namespace + Slack credentials secret
##################################################################################

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
    token = var.slack_bot_token
  }
  type = "Opaque"
}

##################################################################################
# HELM: teleport-plugin-slack
#
# tbot runs as a sidecar inside the plugin pod. It joins via kubernetes join
# (uses the pod's ServiceAccount JWT) and continuously renews the plugin's
# Teleport credentials — no manual certificate rotation needed.
##################################################################################

locals {
  chart_version = var.plugin_chart_version != "" ? var.plugin_chart_version : null

  # Role → Slack channel mapping.
  # Keys are the requestable Teleport roles (matching the requester roles in 3-rbac).
  # devs (dev-requester):               can request prod-readonly-access
  # senior-devs (senior-dev-requester): can request prod-readonly-access, prod-access, prod-auto-access
  # engineers (prod-requester):         can request prod-access, prod-auto-access
  role_to_recipients = {
    "prod-readonly-access" = [var.slack_channel_id]
    "prod-access"          = [var.slack_channel_id]
    "prod-auto-access"     = [var.slack_channel_id]
    "*"                    = [var.slack_channel_id]
  }
}

resource "helm_release" "teleport_plugin_slack" {
  depends_on = [
    kubectl_manifest.provision_token_tbot_slack,
    kubernetes_secret.slack_credentials,
  ]

  name       = "teleport-plugin-slack"
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-plugin-slack"
  namespace  = kubernetes_namespace.plugins.metadata[0].name
  version    = local.chart_version
  wait       = true
  timeout    = 120

  values = [yamlencode({
    teleport = {
      address = "${var.proxy_address}:443"
    }

    # Built-in tbot sidecar — handles Teleport authentication via kubernetes join.
    # Credentials are renewed automatically; no identity file bootstrap needed.
    tbot = {
      enabled              = true
      clusterName          = var.proxy_address
      teleportProxyAddress = "${var.proxy_address}:443"
      joinMethod           = "kubernetes"
      token                = "tbot-slack-plugin"
    }

    slack = {
      token = var.slack_bot_token
    }

    roleToRecipients = local.role_to_recipients

    log = {
      output   = "stdout"
      severity = "INFO"
    }
  })]
}
