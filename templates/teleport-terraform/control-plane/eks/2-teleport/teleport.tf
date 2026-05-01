##################################################################################
# TELEPORT HELM/SERVICE DEPLOYMENT
##################################################################################

resource "kubernetes_service_account" "teleport_auth" {
  metadata {
    name      = "teleport-cluster"
    namespace = kubernetes_namespace.teleport_cluster.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.teleport_auth.arn
    }
  }
}

resource "kubernetes_service_account" "teleport_proxy" {
  metadata {
    name      = "teleport-cluster-proxy"
    namespace = kubernetes_namespace.teleport_cluster.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.teleport_auth.arn
    }
  }
}

resource "kubernetes_service_account" "teleport_operator" {
  metadata {
    name      = "teleport-cluster-operator"
    namespace = kubernetes_namespace.teleport_cluster.metadata[0].name
  }
}

locals {
  # Conditional Access Graph config — populated when var.access_graph_enabled = true.
  # The ConfigMap teleport-access-graph-ca is created by 5-access-graph and mounted
  # at /var/run/access-graph so the auth service can verify the gRPC TLS certificate.
  access_graph_auth_config = var.access_graph_enabled ? {
    teleportConfig = {
      access_graph = {
        enabled  = true
        endpoint = "teleport-access-graph.teleport-access-graph.svc.cluster.local:443"
        ca       = "/var/run/access-graph/ca.pem"
      }
    }
  } : {}

  access_graph_extra_volumes = var.access_graph_enabled ? [
    { name = "tag-ca", configMap = { name = "teleport-access-graph-ca" } }
  ] : []

  access_graph_extra_volume_mounts = var.access_graph_enabled ? [
    { name = "tag-ca", mountPath = "/var/run/access-graph" }
  ] : []
}

resource "helm_release" "teleport_cluster" {
  name       = "teleport-cluster"
  namespace  = kubernetes_namespace.teleport_cluster.metadata[0].name
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-cluster"
  version    = var.teleport_version
  wait       = true
  timeout    = 300
  values = [
    jsonencode({
      clusterName       = var.proxy_address
      proxyListenerMode = "multiplex"
      acme              = false
      tls               = { existingSecretName = "teleport-tls" }
      enterprise        = fileexists("${path.module}/../../license.pem")
      labels            = { env = var.env, team = var.team }
      authentication    = { type = "saml" }
      serviceAccount    = { create = false, name = "teleport-cluster" }
      auth              = merge({ serviceAccount = { create = false, name = "teleport-cluster" } }, local.access_graph_auth_config)
      proxy             = { serviceAccount = { create = false, name = "teleport-cluster-proxy" } }
      operator          = { enabled = true, serviceAccount = { create = false, name = "teleport-cluster-operator" } }
      chartMode         = "aws"
      aws = {
        region                 = var.region
        backendTable           = aws_dynamodb_table.teleport_backend.name
        auditLogTable          = aws_dynamodb_table.teleport_events.name
        auditLogMirrorOnStdout = false
        dynamoAutoScaling      = false
        sessionRecordingBucket = aws_s3_bucket.session_recordings.bucket
      }
      extraVolumes      = local.access_graph_extra_volumes
      extraVolumeMounts = local.access_graph_extra_volume_mounts
    })
  ]
  depends_on = [
    kubectl_manifest.teleport_certificate,
    kubernetes_secret.license,
    kubernetes_service_account.teleport_auth,
    kubernetes_service_account.teleport_proxy,
    kubernetes_service_account.teleport_operator,
    aws_iam_role_policy_attachment.teleport_auth,
    aws_dynamodb_table.teleport_backend,
    aws_dynamodb_table.teleport_events,
    aws_s3_bucket.session_recordings
  ]
}

resource "time_sleep" "wait_for_operator" {
  depends_on      = [helm_release.teleport_cluster]
  create_duration = "60s"
}
