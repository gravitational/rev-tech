locals {
  user_data = <<USER_DATA
#!/usr/bin/env bash
set -e
exec >> /var/log/user_data.log 2>&1

source /etc/os-release

apt-get update

apt-get install -y curl gnupg2 ca-certificates apt-transport-https jq awscli


install -m 0755 -d /var/lib/teleport/

cat <<EOF | tee /etc/teleport.yaml
version: v3
teleport:
  nodename: $(hostname)
  data_dir: /var/lib/teleport
  join_params:
    token_name: ${teleport_provision_token.this.metadata.name}
    method: "iam"
  proxy_server: ${var.proxy}:443
  log:
    output: stderr
    severity: INFO
    format:
      output: text
auth_service:
  enabled: "no"
proxy_service:
  enabled: "no"
ssh_service:
  enabled: "yes"
app_service:
  enabled: "yes"
  apps:
    - name: "demo-awsconsole"
      uri: "https://console.aws.amazon.com/ec2/v2/home"
EOF

curl "https://${var.proxy}/scripts/install.sh" | bash

systemctl enable teleport
systemctl start teleport
  USER_DATA
}
data "aws_ami" "this" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami.discovery_node.ami]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami.discovery_node.owner]
}

resource "aws_launch_template" "this" {
  name_prefix            = var.name
  image_id               = data.aws_ami.this.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.this.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.this.name
  }

  metadata_options {
    instance_metadata_tags = "enabled"
  }

  tag_specifications {
    resource_type = "instance"

    tags = var.tags
  }

  tag_specifications {
    resource_type = "volume"

    tags = var.tags
  }

  user_data = base64encode(local.user_data)

  tags = var.tags
}

resource "aws_autoscaling_group" "this" {
  name_prefix = var.name
  desired_capacity    = var.capacity.desired
  max_size            = var.capacity.max_size
  min_size            = var.capacity.min_size
  vpc_zone_identifier = [aws_subnet.this.id]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = { for k, v in merge(var.tags, { Name : var.name }) : k => v }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}