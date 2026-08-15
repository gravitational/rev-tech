output "dev_access_role" {
  description = "Name of the standing dev access role"
  value       = teleport_role.dev_access.metadata.name
}

output "staging_access_role" {
  description = "Name of the requestable staging role (null when prod_env is not set)"
  value       = try(teleport_role.staging_access[0].metadata.name, null)
}

output "prod_access_role" {
  description = "Name of the requestable prod role (null when prod_env is not set)"
  value       = try(teleport_role.prod_access[0].metadata.name, null)
}

output "prod_access_mfa_role" {
  description = "Name of the requestable prod role with per-session MFA (null when prod_env is not set)"
  value       = try(teleport_role.prod_access_mfa[0].metadata.name, null)
}

output "requester_role" {
  description = "Name of the requester role (null when prod_env is not set)"
  value       = try(teleport_role.requester[0].metadata.name, null)
}

output "reviewer_role" {
  description = "Name of the reviewer role (null when prod_env is not set)"
  value       = try(teleport_role.reviewer[0].metadata.name, null)
}

output "auto_approve_rule" {
  description = "Name of the auto-approve access monitoring rule (null unless prod_env and auto_approve_reason are set)"
  value       = try(teleport_access_monitoring_rule.auto_approve_staging[0].metadata.name, null)
}

output "demo_user_name" {
  description = "Name of the primary local demo user (null when create_demo_user is false)"
  value       = var.create_demo_user ? teleport_user.demo_user[0].metadata.name : null
}

output "demo_user_names" {
  description = "All local demo users (primary + per-workstation extras)"
  value       = var.create_demo_user ? concat([var.demo_user_name], var.extra_demo_user_names) : []
}

output "demo_user_setup" {
  description = "One-time activation steps for the demo user(s)"
  value = var.create_demo_user ? join("\n", compact(concat(
    [for u in concat([var.demo_user_name], var.extra_demo_user_names) :
    "tctl users reset ${u}    # one-time activation: reset link sets password + MFA (enroll MFA on that user's workstation)"],
    [
      "# Log in (local auth, even on SSO-default clusters):",
      "tsh login --proxy=<proxy>:443 --user=${var.demo_user_name} --auth=local",
      local.create_prod ? "# JIT flow — staging approves by policy, prod needs a human review:" : "",
      local.create_prod && var.auto_approve_reason != null ? "#   tsh request create --roles=${try(teleport_role.staging_access[0].metadata.name, "")} --reason='${var.auto_approve_reason}'   # auto-approved" : "",
      local.create_prod ? "#   tsh request create --roles=${try(teleport_role.prod_access[0].metadata.name, "")} --reason='need prod'   # waits for a reviewer" : "",
      local.create_prod ? "# Approving prod requests requires the ${try(teleport_role.reviewer[0].metadata.name, "")} role — grant it to yourself once:" : "",
      local.create_prod ? "#   tctl users update <your-username> --set-roles=<existing-roles>,${try(teleport_role.reviewer[0].metadata.name, "")}" : "",
      local.create_prod ? "#   (SSO users: add the role via your connector mapping or an access list instead)" : "",
    ]
  ))) : null
}
