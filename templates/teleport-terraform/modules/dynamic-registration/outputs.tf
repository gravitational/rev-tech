output "resource_name" {
  value = var.name
}

output "resource_type" {
  value = var.resource_type
}

output "resource_id" {
  value       = var.resource_type == "database" ? teleport_database.this[0].id : teleport_app.this[0].id
  description = "The ID of the registered Teleport resource"
}