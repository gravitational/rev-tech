# SSH Node Module

Creates one or more EC2 instances that automatically install the Teleport SSH service, apply useful demo labels, and register through a short-lived provisioning token.

## Usage

```hcl
module "ssh_nodes" {
  source = "../modules/ssh-node"

  env           = "dev"
  user          = "user@example.com"
  proxy_address = "teleport.example.com"
  team          = "platform"

  agent_count   = 3
  ami_id        = data.aws_ami.linux.id
  instance_type = "t3.micro"

  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]

  tags = {
    owner = "user@example.com"
  }
}
```

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `agent_count` | Number of Teleport SSH nodes to deploy. | `number` | n/a |
| `ami_id` | AMI used for each instance (Amazon Linux 2023 recommended). | `string` | n/a |
| `env` | Environment label added to Teleport labels and Name tag. | `string` | n/a |
| `instance_type` | EC2 instance size. | `string` | n/a |
| `proxy_address` | Teleport proxy host (no scheme, no port). | `string` | n/a |
| `security_group_ids` | Security groups to attach to the instances. | `list(string)` | n/a |
| `subnet_id` | Subnet where the nodes run. | `string` | n/a |
| `team` | Team label assigned to the Teleport nodes. | `string` | n/a |
| `user` | Creator identifier; used for naming and token scoping. | `string` | n/a |
| `tags` | Extra AWS tags merged into every instance. | `map(string)` | `{}` |

## Outputs

| Name | Description |
| --- | --- |
| `provision_token` | The Teleport provisioning token used by the nodes. |
| `private_ips` | Private IP addresses of the created EC2 instances. |
