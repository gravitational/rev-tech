##################################################################################
# CONFIGURATION - Terraform
##################################################################################
terraform {
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 18.0"
    }
  }
}

##################################################################################
# PROVIDERS
##################################################################################
provider "teleport" {
  addr = "${var.proxy_address}:443"
}

##################################################################################
# RBAC — shared role module
# Manages all 12 demo roles. State migration: if you have existing role resources
# in state, run terraform state mv before applying:
#   terraform state mv teleport_role.base_user module.rbac.teleport_role.base_user
#   (repeat for each role that was previously managed here)
##################################################################################
module "rbac" {
  source = "../../../modules/teleport-rbac"
}

output "rbac_summary" {
  value = module.rbac.role_names
}
