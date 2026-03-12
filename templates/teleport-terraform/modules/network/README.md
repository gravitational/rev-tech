# Network Module

Reusable Terraform module that provisions the baseline AWS networking needed for Teleport demos: a VPC, public/private subnets, routing, NAT gateway, and security group.

## Usage

```hcl
module "network" {
  source = "../modules/network"

  env                = "dev"
  name_prefix        = "engineer-dev"
  cidr_vpc           = "10.0.0.0/16"
  cidr_subnet        = "10.0.1.0/24" # private
  cidr_public_subnet = "10.0.0.0/24" # public

  tags = {
    owner = "engineer@example.com"
  }
}
```

Set `name_prefix` to a unique `<user>-<env>` string (for example `engineer-dev`) so multiple engineers can run the module inside the same AWS account without colliding resource names.

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `env` | Environment label used for tagging. | `string` | n/a |
| `cidr_vpc` | CIDR block for the VPC. | `string` | n/a |
| `cidr_subnet` | CIDR block for the private subnet. | `string` | n/a |
| `cidr_public_subnet` | CIDR block for the public subnet. | `string` | n/a |
| `create_secondary_subnet` | Whether to create a second private subnet (required for RDS multi-AZ). | `bool` | `false` |
| `cidr_secondary_subnet` | CIDR block for the second private subnet. | `string` | `""` |
| `create_db_subnet_group` | Whether to build a DB subnet group spanning the available private subnets. | `bool` | `false` |
| `name_prefix` | Prefix applied to every resource name; defaults to `env` when empty. | `string` | `""` |
| `tags` | Extra tags merged into every resource. | `map(string)` | `{}` |

## Outputs

| Name | Description |
| --- | --- |
| `vpc_id` | ID of the created VPC. |
| `subnet_id` | ID of the primary private subnet. |
| `public_subnet_id` | ID of the public subnet. |
| `private_subnet_ids` | Private subnet IDs (one or two items). |
| `security_group_id` | ID of the default security group covering demo nodes. |
| `db_subnet_group_name` | Name of the DB subnet group when created, otherwise `null`. |
