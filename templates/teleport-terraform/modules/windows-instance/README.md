# Windows (Local) Node Module

Creates a Windows EC2 instance that is configured for use with the Teleport Desktop Service. The TDS is running on an adjancent Linux EC2 instance as configured in the desktop-service module. 

## Usage

```hcl
module "windows-instance" {
    source = "../modules/windows-instance"

    env           = "dev"
    user          = "user@example.com"
    proxy_address = "teleport.example.com"
    team          = "platform"

    ami_id        = data.aws_ami.windows.id
    instance_type = "t3.medium"

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
| `ami_id` | AMI ID for Windows Server. | `string` | n/a |
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
| `hostname` | Name of instance. |
| `private_dns` | Private DNS name of Windows instance. |
| `private_ip` | Private IP address of Windows instance. |
