# app-httpbin Module

Deploys an HTTPBin instance on EC2 with the Teleport app service. HTTPBin echoes back all HTTP headers it receives, making it useful for showing Teleport-injected headers (`Teleport-Jwt-Assertion`, `X-Forwarded-User`, etc.) in real time during a demo.

## Usage

```hcl
module "httpbin" {
  source = "../../modules/app-httpbin"

  env           = "dev"
  user          = "engineer@example.com"
  proxy_address = "teleport.example.com"
  team          = "platform"

  teleport_version   = "18.0.0"
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.micro"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| `ami_id` | AMI for the HTTPBin instance (Amazon Linux 2023 recommended). | `string` | n/a |
| `env` | Environment label applied to Teleport and AWS tags. | `string` | n/a |
| `instance_type` | EC2 instance size. | `string` | n/a |
| `proxy_address` | Teleport proxy host (no scheme, no port). | `string` | n/a |
| `security_group_ids` | Security groups to attach to the instance. | `list(string)` | n/a |
| `subnet_id` | Subnet where the instance runs. | `string` | n/a |
| `team` | Team label applied to Teleport and AWS tags. | `string` | `"platform"` |
| `teleport_version` | Teleport version to install. | `string` | n/a |
| `user` | Creator email; used for naming and token scoping. | `string` | n/a |
| `tags` | Extra AWS tags merged into the instance. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|---|---|
| `httpbin_private_ip` | Private IP of the HTTPBin instance. |
