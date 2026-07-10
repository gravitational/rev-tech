output "connection_guide" {
  description = "Quick-reference tsh commands and trust policy setup for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Application Access — AWS Console
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    App host IAM role (Principal for target role trust policies):
      ${module.aws_console_host.iam_role_arn}

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List console apps:
       tsh apps ls env=${var.env},team=${var.team}

    3. Open the AWS Console (generates a pre-signed federated session URL):
       tsh apps login ${var.app_a_name}

    Cross-account trust policy snippet (add to any IAM role this app should assume):
      Effect:    Allow
      Principal: ${module.aws_console_host.iam_role_arn}
      Action:    sts:AssumeRole
      (Add ExternalId condition for account B if app_b_external_id is set)

    ──────────────────────────────────────────────────────
    App A: ${var.app_a_name}
    App B: ${var.enable_app_b ? var.app_b_name : "(disabled — set enable_app_b=true to add)"}
    ──────────────────────────────────────────────────────
  EOT
}

output "host_iam_role_arn" {
  description = "IAM role ARN of the app host — add as Principal in target role trust policies"
  value       = module.aws_console_host.iam_role_arn
}

output "apps" {
  description = "Registered AWS console app names"
  value       = var.enable_app_b ? [var.app_a_name, var.app_b_name] : [var.app_a_name]
}

output "managed_account_a_roles" {
  description = "Account A roles managed by this stack (empty when manage_account_a_roles=false)"
  value       = var.manage_account_a_roles ? [for role in aws_iam_role.account_a : role.name] : []
}
