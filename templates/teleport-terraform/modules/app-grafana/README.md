# app-grafana Module

Deploys a Grafana instance on EC2 with the Teleport app service. Grafana receives the `Teleport-Jwt-Assertion` header so it can use Teleport as its auth proxy — the logged-in Teleport user is passed through to Grafana without a separate login.

## Usage

```hcl
module "grafana" {
  source = "../../modules/app-grafana"

  env           = "dev"
  user          = "engineer@example.com"
  proxy_address = "teleport.example.com"
  team          = "platform"

  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.small"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `ami_id` | AMI for the Grafana instance (Amazon Linux 2023 recommended). | `string` | n/a |
| `env` | Environment label applied to Teleport and AWS tags. | `string` | n/a |
| `instance_type` | EC2 instance size. | `string` | n/a |
| `proxy_address` | Teleport proxy host (no scheme, no port). | `string` | n/a |
| `security_group_ids` | Security groups to attach to the instance. | `list(string)` | n/a |
| `subnet_id` | Subnet where the instance runs. | `string` | n/a |
| `team` | Team label applied to Teleport and AWS tags. | `string` | `"platform"` |
| `user` | Creator email; used for naming and token scoping. | `string` | n/a |
| `tags` | Extra AWS tags merged into the instance. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `grafana_private_ip` | Private IP of the Grafana instance. |
