# ec2-discovery-agent Module

Deploys a Teleport Discovery Service agent that scans the AWS account for EC2 instances matching a tag filter and auto-enrolls them via SSM. Target instances join the Teleport cluster using **IAM joining** — no pre-shared secrets, no manual token passing.

## How it works

1. The discovery agent calls `DescribeInstances` to find tagged EC2 instances.
2. For each unenrolled instance, it sends the `TeleportDiscoveryInstaller` SSM command.
3. The SSM command installs Teleport and configures it to join via IAM.
4. Teleport validates the instance's IAM role ARN against the allow rules in the IAM token — no token value is ever transmitted.

## Pre-requisite

Tag the EC2 instances you want auto-enrolled:

```bash
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=teleport-discovery,Value=enabled
```

The discovery agent polls every ~30 seconds and enrolls newly tagged instances automatically.

## Usage

```hcl
# 1. Create the IAM role for target instances.
resource "aws_iam_role" "target" { ... }

# 2. Deploy the discovery agent, referencing the target role.
module "ec2_discovery" {
  source = "../modules/ec2-discovery-agent"

  env                  = "dev"
  team                 = "platform"
  user                 = "user@example.com"
  proxy_address        = "teleport.example.com"
  teleport_version     = "18.0.0"
  region               = "us-east-2"
  ami_id               = data.aws_ami.linux.id
  target_iam_role_name = aws_iam_role.target.name

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `env` | Environment label | `string` | n/a |
| `team` | Team label for RBAC | `string` | n/a |
| `user` | Creator email | `string` | n/a |
| `proxy_address` | Teleport proxy host (no scheme, no port) | `string` | n/a |
| `teleport_version` | Teleport version to install | `string` | n/a |
| `region` | AWS region to scan for EC2 instances | `string` | n/a |
| `ami_id` | AMI for the agent (Amazon Linux 2023 recommended) | `string` | n/a |
| `instance_type` | EC2 instance type | `string` | `"t3.small"` |
| `subnet_id` | Subnet where the agent runs | `string` | n/a |
| `security_group_ids` | Security groups to attach | `list(string)` | n/a |
| `tags` | Extra AWS tags | `map(string)` | `{}` |
| `ec2_tag_key` | AWS tag key to filter target instances | `string` | `"teleport-discovery"` |
| `ec2_tag_value` | AWS tag value to filter target instances | `string` | `"enabled"` |
| `target_iam_role_name` | IAM role name on target instances (scopes the IAM join token) | `string` | n/a |

## Outputs

| Name | Description |
| --- | --- |
| `instance_id` | EC2 instance ID of the discovery agent |
| `iam_role_arn` | ARN of the agent's IAM role |
| `join_token_name` | Name of the IAM join token for target instances |
| `discovery_group` | Teleport discovery group name (`env-team`) |
