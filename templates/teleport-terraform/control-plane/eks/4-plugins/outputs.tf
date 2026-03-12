output "plugin_namespace" {
  description = "Kubernetes namespace the Slack plugin is deployed into"
  value       = kubernetes_namespace.plugins.metadata[0].name
}

output "tbot_status" {
  description = "Commands to verify tbot and plugin health"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Verify tbot (Machine ID) is running and issuing certs
    ──────────────────────────────────────────────────────

    tbot pod logs:
      kubectl logs -n ${kubernetes_namespace.plugins.metadata[0].name} \
        -l app=tbot-slack-plugin --tail=50

    Identity secret (populated by tbot after first join):
      kubectl get secret teleport-plugin-slack-identity \
        -n ${kubernetes_namespace.plugins.metadata[0].name}

    Plugin pod logs:
      kubectl logs -n ${kubernetes_namespace.plugins.metadata[0].name} \
        -l app.kubernetes.io/name=teleport-plugin-slack --tail=50

    ──────────────────────────────────────────────────────
    Demo flow
    ──────────────────────────────────────────────────────

    As bob (dev-requester — can only request prod-readonly-access):
      tsh request create --roles=prod-readonly-access \
        --reason="Investigating prod incident"

    As alice (senior-dev-requester — can also request prod-access):
      tsh request create --roles=prod-access \
        --reason="Hotfix deployment needs prod DB access"

    → Slack notification fires in channel ${var.slack_channel_id}
    → engineer (prod-reviewer) clicks Approve or Deny in Slack

    As the requester after approval:
      tsh request ls
      tsh login --request-id=<id>
      tsh ssh ec2-user@<prod-node>

    ──────────────────────────────────────────────────────
    Role → Slack channel mapping
    ──────────────────────────────────────────────────────

    prod-readonly-access → ${var.slack_channel_id}
    prod-access          → ${var.slack_channel_id}
    prod-auto-access     → ${var.slack_channel_id}
    * (catch-all)        → ${var.slack_channel_id}

    ──────────────────────────────────────────────────────
  EOT
}
