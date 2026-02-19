output "host_instance_id" {
  description = "ID of the shared AWS console app host"
  value       = module.aws_console_host.instance_id
}

output "host_public_ip" {
  description = "Public IP of the shared AWS console app host"
  value       = module.aws_console_host.public_ip
}

output "host_iam_role_arn" {
  description = "IAM role ARN assumed by the app host when requesting AWS Console sign-in"
  value       = module.aws_console_host.iam_role_arn
}

output "apps" {
  description = "Registered AWS console app names"
  value       = var.enable_app_b ? [var.app_a_name, var.app_b_name] : [var.app_a_name]
}

output "account_a_trust_policy_json" {
  description = "Trust policy JSON for account A target roles (informational; applied automatically when manage_account_a_roles=true)"
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowTeleportAppHostAssume"
        Effect = "Allow"
        Principal = {
          AWS = module.aws_console_host.iam_role_arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

output "managed_account_a_roles" {
  description = "Account A roles managed by this stack"
  value       = var.manage_account_a_roles ? [for role in aws_iam_role.account_a : role.name] : []
}

output "account_b_trust_policy_json" {
  description = "Trust policy JSON to attach to target roles in account B when app B is enabled"
  value = var.enable_app_b ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      var.app_b_external_id != null ? {
        Sid    = "AllowTeleportAppHostAssumeWithExternalId"
        Effect = "Allow"
        Principal = {
          AWS = module.aws_console_host.iam_role_arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.app_b_external_id
          }
        }
        } : {
        Sid    = "AllowTeleportAppHostAssume"
        Effect = "Allow"
        Principal = {
          AWS = module.aws_console_host.iam_role_arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  }) : null
}
