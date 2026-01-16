output "ca_cert" {
  description = "The custom CA cert used to sign the DB TLS cert"
  value       = tls_self_signed_cert.ca_cert.cert_pem
}