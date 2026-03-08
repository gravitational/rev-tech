# kube-discovery-agent Module

Deploys a single EC2 instance running Teleport with both `kubernetes_service` and `discovery_service` enabled. The discovery service scans the AWS account for EKS clusters matching a tag filter and auto-enrolls them (creates EKS access entries). The kubernetes service proxies `tsh kube login` connections to every enrolled cluster.

**Requires:** Teleport 15+ and EKS 1.23+ (access entries API).

## Pre-requisite

Tag each EKS cluster you want Teleport to discover:

```bash
aws eks tag-resource \
  --resource-arn arn:aws:eks:REGION:ACCOUNT:cluster/CLUSTER-NAME \
  --tags teleport-discovery=enabled
```

The agent polls every ~30 seconds and enrolls newly tagged clusters automatically.

## Usage

```hcl
module "kube_agent" {
  source = "../modules/kube-discovery-agent"

  env              = "dev"
  team             = "platform"
  user             = "user@example.com"
  proxy_address    = "teleport.example.com"
  teleport_version = "18.0.0"
  region           = "us-east-2"
  ami_id           = data.aws_ami.linux.id

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]

  eks_tag_key   = "teleport-discovery"  # default
  eks_tag_value = "enabled"             # default
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
| `region` | AWS region to scan for EKS clusters | `string` | n/a |
| `ami_id` | AMI for the agent (Amazon Linux 2023 recommended) | `string` | n/a |
| `instance_type` | EC2 instance type | `string` | `"t3.small"` |
| `subnet_id` | Subnet where the agent runs | `string` | n/a |
| `security_group_ids` | Security groups to attach | `list(string)` | n/a |
| `tags` | Extra AWS tags | `map(string)` | `{}` |
| `eks_tag_key` | AWS tag key to filter EKS clusters | `string` | `"teleport-discovery"` |
| `eks_tag_value` | AWS tag value to filter EKS clusters | `string` | `"enabled"` |
| `discovery_regions` | AWS regions to scan for EKS clusters. `null` (default) scans the same region as the agent (`var.region`). | `list(string)` | `null` |

## Outputs

| Name | Description |
| --- | --- |
| `instance_id` | EC2 instance ID of the agent |
| `iam_role_arn` | ARN of the IAM role (for reference or cross-account grants) |
| `iam_role_name` | Name of the IAM role |
| `discovery_group` | Teleport discovery group name (`env-team`) |
