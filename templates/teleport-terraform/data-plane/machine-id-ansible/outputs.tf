output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Machine ID — Ansible Automation
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 3–5 minutes after apply for the Ansible host to register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. Find the Ansible host and SSH in:
       tsh ls env=${var.env}
       tsh ssh ec2-user@<ansible-host>

    3. On the host — build inventory from live Teleport node names and run playbook:
       tsh ls env=${var.env} --format=json | jq -r '.[].spec.hostname' > ~/ansible/hosts
       cd ~/ansible && ansible-playbook -i hosts playbook.yaml

    4. Every Ansible-initiated SSH session appears in the Teleport audit log:
       tsh recordings ls

    ──────────────────────────────────────────────────────
    Bot scope: nodes with labels env=${var.env}, team=${var.team}
    SSH config: /opt/machine-id/ssh_config (on the Ansible host)
    ──────────────────────────────────────────────────────
  EOT
}
