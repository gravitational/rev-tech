output "rbac_summary" {
  value       = module.rbac.role_names
  description = "Map of role names created by the teleport-rbac module"
}
