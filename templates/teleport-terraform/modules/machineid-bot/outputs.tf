output "bot_token" {
  description = "The token used by tbot for Machine ID"
  value       = one(concat(teleport_provision_token.bot[*].metadata.name, teleport_provision_token.bot_iam[*].metadata.name))
}

output "bot_registration_secret" {
  description = "One-time registration secret for bound keypair onboarding. Marked sensitive so it never lands in apply output or CI logs — retrieve deliberately with: terraform output -raw bot_registration_secret"
  # Always null on the 18.x provider: its provision_token `status` is optional,
  # not computed, so the server-generated secret is never read back into
  # state. Use join_method = "iam" on EC2, or onboarding_initial_public_key.
  value     = try(teleport_provision_token.bot[0].status.bound_keypair.registration_secret, null)
  sensitive = true
}

output "bot_name" {
  description = "The name of the bot"
  value       = teleport_bot.this.metadata.name
}

output "role_id" {
  description = "The role ID assigned to the bot"
  value       = teleport_role.machine.id
}
