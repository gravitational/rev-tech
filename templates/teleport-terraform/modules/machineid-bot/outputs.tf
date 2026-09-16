output "bot_token" {
  description = "The token used by tbot for Machine ID"
  value       = teleport_provision_token.bot.metadata.name
}

output "bot_registration_secret" {
  description = "One-time registration secret for bound keypair onboarding. Marked sensitive so it never lands in apply output or CI logs — retrieve deliberately with: terraform output -raw bot_registration_secret"
  value       = try(teleport_provision_token.bot.status.bound_keypair.registration_secret, null)
  sensitive   = true
}

output "bot_name" {
  description = "The name of the bot"
  value       = teleport_bot.this.metadata.name
}

output "role_id" {
  description = "The role ID assigned to the bot"
  value       = teleport_role.machine.id
}
