output "connection_guide" {
  description = "Quick-reference tsh commands for everything enabled in this deployment"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Profile: ${var.profile_label}
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Login:
       tsh login --proxy=${var.proxy_address}:443
    %{~if var.create_demo_rbac}
       # as the developer persona (activate first — see the demo_user_setup output):
       tsh login --proxy=${var.proxy_address}:443 --user=${var.demo_user_name} --auth=local
    %{~endif}
    %{~if var.enable_ssh}

    SSH nodes:
       tsh ls env=${var.env},team=${var.team}
       tsh ssh ec2-user@${var.env}-ssh-0
    %{~endif}
    %{~if var.enable_ssh_prod}

    Access request demo (prod node is invisible until approved):
       tsh request create --roles=${var.create_demo_rbac ? "${local.user_prefix}-prod-readonly" : "prod-readonly-access"} --reason="check prod logs"
       # approver: tsh request review <request-id> --approve --reason="ok"
       # then: tsh ls shows ${var.prod_env}-ssh-0
       tsh ssh ec2-user@${var.prod_env}-ssh-0
    %{~endif}
    %{~if var.enable_postgres || var.enable_mysql || var.enable_mongodb || var.enable_cassandra || var.enable_rds_mysql}

    Databases (cert/IAM auth — no passwords):
       tsh db ls env=${var.env},team=${var.team}
    %{~endif}
    %{~if var.enable_postgres}
       tsh db connect postgres-${var.env} --db-user=writer --db-name=postgres
    %{~endif}
    %{~if var.enable_mysql}
       tsh db connect mysql-${var.env} --db-user=writer
    %{~endif}
    %{~if var.enable_mongodb}
       tsh db connect mongodb-${var.env} --db-user=writer
    %{~endif}
    %{~if var.enable_cassandra}
       tsh db connect cassandra-${var.env} --db-user=writer
    %{~endif}
    %{~if var.enable_rds_mysql}
       tsh db connect rds-mysql-${var.env}
    %{~endif}
    %{~if var.enable_grafana || var.enable_httpbin || var.enable_demo_panel || var.enable_aws_console}

    Applications:
       tsh apps ls env=${var.env},team=${var.team}
    %{~endif}
    %{~if var.enable_grafana}
       tsh apps login grafana-${var.env}
    %{~endif}
    %{~if var.enable_httpbin}
       tsh apps login httpbin-${var.env}     # open /headers to see injected identity
    %{~endif}
    %{~if var.enable_demo_panel}
       tsh apps login demo-panel-${var.env}
    %{~endif}
    %{~if var.enable_aws_console}
       tsh apps login awsconsole-${var.env}
    %{~endif}
    %{~if var.enable_mcp}

    MCP / AI integration (read-only tool allowlist):
       tsh mcp ls
       tsh mcp config mcp-filesystem-${var.env}
       # Paste into Claude Desktop, Cursor, or any MCP client
    %{~endif}
    %{~if var.enable_ansible}

    Ansible Machine ID:
       tsh ssh ec2-user@${var.env}-ansible   # then: cd ansible && ansible-playbook -i hosts playbook.yaml
    %{~endif}
    %{~if var.enable_windows}

    Windows Desktop (web UI only):
       https://${var.proxy_address}/web/desktops
    %{~endif}

    Audit trail:
       tsh recordings ls

    ──────────────────────────────────────────────────────
    Destroy when done: terraform destroy ${var.profile_label != "custom" ? "-var-file=presets/${var.profile_label}.tfvars" : ""}
    ──────────────────────────────────────────────────────
  EOT
}

output "demo_user_setup" {
  description = "One-time activation steps for the demo user (null when create_demo_rbac is false)"
  value       = var.create_demo_rbac ? module.demo_rbac[0].demo_user_setup : null
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint address (null unless enable_rds_mysql)"
  value       = var.enable_rds_mysql ? module.rds_mysql[0].rds_endpoint : null
}
