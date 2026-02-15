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
      operator          = { enabled = true }
      authentication    = { type = "saml" }
      serviceAccount    = { create = false, name = "teleport-cluster" }
      auth              = { serviceAccount = { create = false, name = "teleport-cluster" } }
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
