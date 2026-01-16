terraform {
  required_providers {
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
    }
  }
}

resource "teleport_database" "this" {
  count = var.resource_type == "database" ? 1 : 0

  version = "v3"
  metadata = {
    name        = var.name
    description = var.description
    labels = merge(var.labels, {
      "teleport.dev/origin"    = "dynamic"
      "teleport.dev/db-access" = var.db_access_pattern
    })
  }
  spec = {
    protocol = var.protocol
    uri      = var.uri
    tls = {
      ca_cert = var.ca_cert_chain
    }
  }
}

# fix for dyanmic block within map spec: assignment 
locals {
  base_spec = {
    uri                  = var.uri
    public_addr          = var.public_addr
    insecure_skip_verify = var.insecure_skip_verify
  }

  rewrite_spec = length(var.rewrite_headers) > 0 ? {
    rewrite = {
      headers = [
        for header in var.rewrite_headers : {
          name  = split(":", header)[0]
          value = trimspace(join(":", slice(split(":", header), 1, length(split(":", header)))))
        }
      ]
    }
  } : {}

  app_spec = merge(local.base_spec, local.rewrite_spec)
}

resource "teleport_app" "this" {
  count   = var.resource_type == "app" ? 1 : 0
  version = "v3"

  metadata = {
    name        = var.name
    description = var.description
    labels      = merge(var.labels, { "teleport.dev/origin" = "dynamic" })
  }

  spec = local.app_spec
}