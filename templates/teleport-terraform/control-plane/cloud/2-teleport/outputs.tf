output "cluster_url" {
  value       = "https://${var.proxy_address}"
  description = "Teleport Cloud cluster URL"
}

output "saml_connector_name" {
  value       = teleport_saml_connector.okta.metadata.name
  description = "Name of the SAML connector created"
}
