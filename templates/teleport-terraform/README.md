# Teleport Terraform Templates

Repository of Terraform templates and reusable modules that Solution Engineers can use to demonstrate Teleport features on AWS.

## Layout

```
templates/teleport-terraform/
├── modules/
│   ├── network/      # shared VPC/subnet/NAT scaffolding
│   └── ssh-node/     # EC2 nodes running Teleport SSH service
└── server-access-ssh-getting-started/ # template mirroring the official SSH getting started guide
```

## Templates

- **server-access-ssh-getting-started** – deploys a small Amazon Linux cluster running the Teleport SSH service for demos or workshops. See its README for prerequisites and usage.

More templates (e.g., Windows access, database access, app proxies) will be added over time using the common modules in this directory.

## Modules

- **network** – builds a VPC with public/private subnets, NAT gateway, and security group. Takes `name_prefix` and `tags` inputs so multiple engineers can safely deploy side by side.
- **ssh-node** – launches EC2 instances that install Teleport via the cluster script and register with dynamic labels for RBAC demos.

Each module includes its own README with usage and variable details.
