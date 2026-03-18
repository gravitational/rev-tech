output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Server Access — SSH Getting Started
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 2–3 minutes after apply for nodes to register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List enrolled nodes:
       tsh ls env=${var.env}

    3. SSH to a node:
       tsh ssh ec2-user@<node-name>

    4. Show dynamic labels (CPU, instance-id, etc.) updating live:
       tsh ls env=${var.env} --format=json | jq '.[].spec.cmd_labels'

    5. View session recordings after connecting:
       tsh recordings ls

    ──────────────────────────────────────────────────────
    Nodes deployed: ${var.agent_count}
    Node labels: env=${var.env}, team=${var.team}
    ──────────────────────────────────────────────────────
  EOT
}
