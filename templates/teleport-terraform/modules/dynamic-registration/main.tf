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

# fix for dynamic block within map spec: assignment
locals {
  base_spec = merge(
    var.uri != null ? { uri = var.uri } : {},
    var.public_addr != null ? { public_addr = var.public_addr } : {},
    var.insecure_skip_verify ? { insecure_skip_verify = true } : {}
  )

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

  mcp_spec = var.mcp_command != null ? {
    mcp = merge(
      { command = var.mcp_command, args = var.mcp_args },
      var.mcp_run_as_host_user != null ? { run_as_host_user = var.mcp_run_as_host_user } : {}
    )
  } : {}

  aws_spec = var.app_aws_external_id != null ? {
    aws = {
      external_id = var.app_aws_external_id
    }
  } : {}

  app_spec = merge(local.base_spec, local.rewrite_spec, local.mcp_spec, local.aws_spec)
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
