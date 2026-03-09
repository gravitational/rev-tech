# control-plane/eks/5-access-graph/main.tf
#
# Deploys Teleport Access Graph (Identity Security) into the EKS cluster.
# Depends on: 1-cluster (remote state), 2-teleport (cluster running), 3-rbac (roles exist).
#
# What gets created:
#   AWS resources:
#     - RDS Aurora Serverless v2 (PostgreSQL 16) — Access Graph database
#     - DB subnet group + security group in the EKS VPC
#
#   Kubernetes resources:
#     - Namespace:   teleport-access-graph
#     - Secret:      teleport-access-graph-postgres  (RDS connection URI)
#     - Secret:      teleport-access-graph-tls       (gRPC TLS cert/key)
#     - ConfigMap:   teleport-access-graph-ca        (in teleport-cluster namespace)
#     - Helm release: teleport-access-graph
#
# After applying, re-apply 2-teleport with:
#   TF_VAR_access_graph_enabled=true terraform apply
#
# The ConfigMap teleport-access-graph-ca is mounted by the auth pods
# once 2-teleport is updated — no manual steps needed.

locals {
  chart_version = var.access_graph_chart_version != "" ? var.access_graph_chart_version : null
}

##################################################################################
# TLS CERTIFICATE (self-signed, scoped to internal Kubernetes service DNS)
##################################################################################

resource "tls_private_key" "access_graph" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "access_graph" {
  private_key_pem = tls_private_key.access_graph.private_key_pem

  subject {
    common_name  = "teleport-access-graph"
    organization = "Teleport Access Graph"
  }

  validity_period_hours = 8760 # 1 year

  dns_names = [
    "teleport-access-graph",
    "teleport-access-graph.teleport-access-graph",
    "teleport-access-graph.teleport-access-graph.svc",
    "teleport-access-graph.teleport-access-graph.svc.cluster.local",
  ]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

##################################################################################
# KUBERNETES: namespace, secrets, ConfigMap
##################################################################################

resource "kubernetes_namespace" "access_graph" {
  metadata {
    name = "teleport-access-graph"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# PostgreSQL connection URI — read by the Access Graph Helm chart
resource "kubernetes_secret" "access_graph_postgres" {
  metadata {
    name      = "teleport-access-graph-postgres"
    namespace = kubernetes_namespace.access_graph.metadata[0].name
  }
  data = {
    uri = "postgres://access_graph:${var.db_password}@${aws_rds_cluster.access_graph.endpoint}:5432/access_graph?sslmode=require"
  }
  type       = "Opaque"
  depends_on = [aws_rds_cluster_instance.access_graph]
}

# TLS certificate for the Access Graph gRPC listener
resource "kubernetes_secret" "access_graph_tls" {
  metadata {
    name      = "teleport-access-graph-tls"
    namespace = kubernetes_namespace.access_graph.metadata[0].name
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = tls_self_signed_cert.access_graph.cert_pem
    "tls.key" = tls_private_key.access_graph.private_key_pem
  }
}

# CA cert ConfigMap in the Teleport namespace — mounted by 2-teleport auth pods
# so the auth service can verify the Access Graph TLS certificate.
resource "kubernetes_config_map" "access_graph_ca" {
  metadata {
    name      = "teleport-access-graph-ca"
    namespace = var.teleport_namespace
  }
  data = {
    "ca.pem" = tls_self_signed_cert.access_graph.cert_pem
  }
}

##################################################################################
# HELM: teleport-access-graph
##################################################################################

resource "helm_release" "access_graph" {
  depends_on = [
    kubernetes_secret.access_graph_postgres,
    kubernetes_secret.access_graph_tls,
    aws_rds_cluster_instance.access_graph,
  ]

  name       = "teleport-access-graph"
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-access-graph"
  namespace  = kubernetes_namespace.access_graph.metadata[0].name
  version    = local.chart_version
  wait       = true
  timeout    = 300

  values = [yamlencode({
    replicaCount = 1

    postgres = {
      secretName = kubernetes_secret.access_graph_postgres.metadata[0].name
    }

    tls = {
      existingSecretName = kubernetes_secret.access_graph_tls.metadata[0].name
    }

    # List of PEM-encoded Teleport host CA certs allowed to connect to this instance.
    # Retrieve with: curl 'https://<proxy>/webapi/auth/export?type=tls-host'
    clusterHostCAs = [var.teleport_host_ca]
  })]
}
