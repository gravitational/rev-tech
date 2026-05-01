# 3-rbac/outputs.tf

output "scim_bootstrap_command" {
  description = "Run this once after applying this layer to register the SCIM plugin"
  value       = <<-EOT

    AUTH_POD=$(kubectl get pod -n teleport-cluster \
      -l app.kubernetes.io/component=auth \
      -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n teleport-cluster "$AUTH_POD" -- \
      tctl plugins install scim --connector=okta-integrator

  EOT
}
