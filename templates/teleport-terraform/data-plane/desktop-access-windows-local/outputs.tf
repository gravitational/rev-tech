output "windows_node_ip" {
  value = module.windows_instance.private_ip
}

output "desktop_service_ip" {
  value = module.linux_desktop_service.private_ip
}