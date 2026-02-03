##################################################################################
# CERT-MANAGER INSTALLATION & CLUSTER ISSUERS
##################################################################################

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.16.2"
  create_namespace = true
  wait            = true
  timeout         = 300
  set {
    name  = "crds.enabled"
    value = "true"
  }
  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }
  set {
    name  = "prometheus.enabled"
    value = "true"
  }
}

resource "kubernetes_annotations" "cert_manager_sa" {
  count       = var.domain_name != "" ? 1 : 0
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = "cert-manager"
    namespace = "cert-manager"
  }
  annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager[0].arn
  }
  depends_on = [
    helm_release.cert_manager,
    aws_iam_role_policy_attachment.cert_manager_route53
  ]
  force = true
}

resource "time_sleep" "wait_for_cert_manager" {
  depends_on      = [kubernetes_annotations.cert_manager_sa]
  create_duration = "90s"
}

resource "kubectl_manifest" "letsencrypt_prod_issuer" {
  depends_on = [time_sleep.wait_for_cert_manager]
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = { name = "letsencrypt-prod" }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.user
        privateKeySecretRef = { name = "letsencrypt-prod-account-key" }
        solvers = [
          {
            dns01 = { route53 = { region = var.region } }
            selector = { dnsZones = [var.domain_name] }
          }
        ]
      }
    }
  })
}

resource "time_sleep" "wait_for_issuer" {
  depends_on      = [kubectl_manifest.letsencrypt_prod_issuer]
  create_duration = "60s"
}

resource "kubectl_manifest" "selfsigned_issuer" {
  depends_on = [time_sleep.wait_for_cert_manager]
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = { name = "selfsigned-issuer" }
    spec = { selfSigned = {} }
  })
}

resource "kubectl_manifest" "teleport_certificate" {
  depends_on = [time_sleep.wait_for_issuer, kubernetes_namespace.teleport_cluster]
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "teleport-tls"
      namespace = kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      secretName = "teleport-tls"
      issuerRef = { name = "letsencrypt-prod", kind = "ClusterIssuer" }
      dnsNames = [var.proxy_address, "*.${var.proxy_address}"]
      duration    = "2160h"
      renewBefore = "720h"
    }
  })
}
