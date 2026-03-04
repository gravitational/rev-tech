output "plugin_service_user" {
  description = "Teleport user name for the Slack plugin service account"
  value       = "slack-plugin-service"
}

output "plugin_namespace" {
  description = "Kubernetes namespace the Slack plugin is deployed into"
  value       = kubernetes_namespace.plugins.metadata[0].name
}

output "bootstrap_commands" {
  description = "One-time commands to generate and register the plugin identity"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    4-plugins bootstrap (run once after first apply)
    ──────────────────────────────────────────────────────

    1. Generate plugin identity file (valid for 1 year):
       tctl auth sign --format=file \
         --user=slack-plugin-service \
         --out=plugin-identity \
         --ttl=8760h

    2. Store as a Kubernetes secret:
       kubectl create secret generic teleport-plugin-slack-identity \
         --from-file=auth_id=plugin-identity \
         -n ${kubernetes_namespace.plugins.metadata[0].name}

    3. Restart the plugin deployment:
       kubectl rollout restart deployment/teleport-plugin-slack \
         -n ${kubernetes_namespace.plugins.metadata[0].name}

    ──────────────────────────────────────────────────────
    Demo flow (after bootstrap)
    ──────────────────────────────────────────────────────

    As a dev user (has dev-requester role):
       tsh request create --roles=prod-readonly-access \
         --reason="Need to investigate prod incident"

    → Slack notification fires in channel ${var.slack_channel_id}
    → Reviewer clicks Approve or Deny in Slack

    As the same user (after approval):
       tsh request ls
       tsh login --request-id=<id>   # activates the elevated role
       tsh ssh ec2-user@<prod-node>   # now has prod SSH access

    ──────────────────────────────────────────────────────
    Role → Slack channel mapping
    ──────────────────────────────────────────────────────

    prod-access          → ${var.slack_channel_id}
    prod-readonly-access → ${var.slack_channel_id}
    platform-dev-access  → ${var.slack_channel_id}
    * (catch-all)        → ${var.slack_channel_id}

    ──────────────────────────────────────────────────────
  EOT
}
