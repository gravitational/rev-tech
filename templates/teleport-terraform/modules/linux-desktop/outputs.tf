output "instance_id" {
  description = "EC2 instance ID of the Linux desktop host"
  value       = aws_instance.linux_desktop.id
}

output "private_ip" {
  description = "Private IP of the Linux desktop host"
  value       = aws_instance.linux_desktop.private_ip
}

output "hostname" {
  description = "Hostname the desktop registers under in Teleport"
  value       = "${var.env}-linux-desktop"
}

output "access_role_name" {
  description = "Name of the linux-desktop-access role (null when create_access_role is false)"
  value       = var.create_access_role ? teleport_role.linux_desktop_access[0].metadata.name : null
}
