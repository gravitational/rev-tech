output "connection_guide" {
  description = "Quick-reference tsh commands and enrollment notes for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Server Access – EC2 Auto-Discovery
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    ${var.target_count} target EC2 instances were created tagged with:
      ${var.ec2_tag_key}=${var.ec2_tag_value}

    The discovery agent installs Teleport on them via SSM within ~60 seconds.
    Targets join using IAM joining — no token value is ever transmitted.

    To enroll an existing EC2 instance, tag it:
      aws ec2 create-tags \
        --resources <instance-id> \
        --tags Key=${var.ec2_tag_key},Value=${var.ec2_tag_value}

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List auto-enrolled nodes (wait ~60 s after apply):
       tsh ls env=${var.env}

    3. SSH into a node:
       tsh ssh ec2-user@<node-name>

    4. Show node labels (AWS tags become Teleport labels automatically):
       tsh ls --format=json | jq '.[].spec.labels'

    ──────────────────────────────────────────────────────
    IAM join token: ${module.ec2_discovery.join_token_name}
    Discovery group: ${module.ec2_discovery.discovery_group}
    ──────────────────────────────────────────────────────
  EOT
}

output "target_instance_ids" {
  description = "Instance IDs of the auto-discovery target EC2 instances"
  value       = aws_instance.target[*].id
}

output "discovery_agent_id" {
  description = "EC2 instance ID of the Teleport discovery agent"
  value       = module.ec2_discovery.instance_id
}
