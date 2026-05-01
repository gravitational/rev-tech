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
# SAML CONNECTOR
##################################################################################

resource "teleport_saml_connector" "okta" {
  version = "v2"

  metadata = {
    name = "okta"
  }

  spec = {
    attributes_to_roles = [
      # All authenticated users -> base-user
      {
        name  = "groups"
        value = "Everyone"
        roles = ["base-user"]
      }
    ]

    acs                     = "https://${var.proxy_address}/v1/webapi/saml/acs/okta"
    entity_descriptor_url   = var.okta_metadata_url
    service_provider_issuer = "https://${var.proxy_address}/v1/webapi/saml/acs/okta"
  }
}

##################################################################################
# AUTH PREFERENCE
##################################################################################

resource "teleport_auth_preference" "main" {
  depends_on = [teleport_saml_connector.okta]

  version = "v2"

  metadata = {
    description = "auth preference"
    labels = {
      name                  = "cluster-auth-preference"
      "teleport.dev/origin" = "dynamic"
    }
  }

  spec = {
    type          = "saml"
    second_factor = "on" # allow OTP and WebAuthn

    webauthn = {
      rp_id = var.proxy_address
    }

    connector_name     = teleport_saml_connector.okta.metadata.name
    allow_local_auth   = true
    allow_passwordless = true
  }
}

##################################################################################
# RBAC RESOURCES LIVE IN 3-rbac
##################################################################################
