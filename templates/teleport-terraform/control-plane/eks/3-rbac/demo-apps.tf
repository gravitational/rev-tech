
# 2-kubernetes-config/demo-apps.tf
#
# Usage notes:
# - All demo namespaces and apps use labels 'env' and 'team' for Teleport RBAC.
# - Example teams: dev, platform
# - Teleport roles in roles.tf grant access based on these labels.
# - Example: tsh apps ls env=dev,team=dev
#
# To add more teams, duplicate resources with different 'team' values.

# Demo Namespaces

resource "kubernetes_namespace" "dev" {
  metadata {
    name = "dev"
    labels = {
      env  = "dev"
      team = var.dev_team
    }
  }
}

resource "kubernetes_namespace" "prod" {
  metadata {
    name = "prod"
    labels = {
      env  = "prod"
      team = var.prod_team
    }
  }
}

# Demo Applications - Web Apps

resource "kubernetes_deployment" "webapp_dev" {
  metadata {
    name      = "webapp"
    namespace = kubernetes_namespace.dev.metadata[0].name
    labels = {
      env  = "dev"
      team = var.dev_team
    }
  }
  spec {
    selector {
      match_labels = {
        app  = "nginx-webapp"
        env  = "dev"
        team = var.dev_team
      }
    }
    template {
      metadata {
        labels = {
          app  = "nginx-webapp"
          env  = "dev"
          team = var.dev_team
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.23"
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.dev]
}


resource "kubernetes_deployment" "webapp_prod" {
  metadata {
    name      = "webapp"
    namespace = kubernetes_namespace.prod.metadata[0].name
    labels = {
      env  = "prod"
      team = var.prod_team
    }
  }
  spec {
    selector {
      match_labels = {
        app  = "nginx-webapp"
        env  = "prod"
        team = var.prod_team
      }
    }
    template {
      metadata {
        labels = {
          app  = "nginx-webapp"
          env  = "prod"
          team = var.prod_team
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.23"
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.prod]
}

# Demo Applications - Load Balancers

resource "kubernetes_deployment" "loadbalancer_dev" {
  metadata {
    name      = "loadbalancer"
    namespace = kubernetes_namespace.dev.metadata[0].name
    labels = {
      env  = "dev"
      team = var.dev_team
    }
  }
  spec {
    selector {
      match_labels = {
        app  = "nginx-loadbalancer"
        env  = "dev"
        team = var.dev_team
      }
    }
    template {
      metadata {
        labels = {
          app  = "nginx-loadbalancer"
          env  = "dev"
          team = var.dev_team
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.23"
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.dev]
}


resource "kubernetes_deployment" "loadbalancer_prod" {
  metadata {
    name      = "loadbalancer"
    namespace = kubernetes_namespace.prod.metadata[0].name
    labels = {
      env  = "prod"
      team = var.prod_team
    }
  }
  spec {
    selector {
      match_labels = {
        app  = "nginx-loadbalancer"
        env  = "prod"
        team = var.prod_team
      }
    }
    template {
      metadata {
        labels = {
          app  = "nginx-loadbalancer"
          env  = "prod"
          team = var.prod_team
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.23"
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.prod]
}
