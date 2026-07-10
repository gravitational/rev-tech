output "dev_access_role" {
  description = "Name of the dev access role"
  value       = teleport_role.dev_access.metadata.name
}

output "prod_readonly_role" {
  description = "Name of the prod readonly role (null when prod_env is not set)"
  value       = var.prod_env != null ? teleport_role.prod_readonly[0].metadata.name : null
}

output "dev_requester_role" {
  description = "Name of the requester role (null when prod_env is not set)"
  value       = var.prod_env != null ? teleport_role.dev_requester[0].metadata.name : null
}

output "prod_reviewer_role" {
  description = "Name of the reviewer role (null when prod_env is not set)"
  value       = var.prod_env != null ? teleport_role.prod_reviewer[0].metadata.name : null
}

output "demo_user_name" {
  description = "Name of the local demo user (null when create_demo_user is false)"
  value       = var.create_demo_user ? teleport_user.demo_user[0].metadata.name : null
}

output "demo_user_setup" {
  description = "One-time activation steps for the demo user"
  value = var.create_demo_user ? join("\n", compact([
    "# Activate ${var.demo_user_name} (one time): generates a reset link to set password + MFA",
    "tctl users reset ${var.demo_user_name}",
    "# Log in as ${var.demo_user_name} (local auth, even on SSO-default clusters):",
    "tsh login --proxy=<proxy>:443 --user=${var.demo_user_name} --auth=local",
    var.prod_env != null ? "# Approving requests requires the ${var.name_prefix}-prod-reviewer role — grant it to yourself once:" : "",
    var.prod_env != null ? "#   tctl users update <your-username> --set-roles=$(tctl get user/<your-username> --format=json | jq -r '.[0].spec.roles | join(\",\")'),${var.name_prefix}-prod-reviewer" : "",
    var.prod_env != null ? "#   (SSO users: add the role via your connector mapping or an access list instead)" : "",
  ])) : null
}
