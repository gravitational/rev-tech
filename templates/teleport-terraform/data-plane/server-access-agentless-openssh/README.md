# Agentless OpenSSH Access

Demonstrates Teleport's agentless SSH access: EC2 instances running standard sshd with no Teleport agent installed. Teleport's proxy routes sessions to these hosts by trusting Teleport's user CA certificate.

This covers the **Enterprise** "Agentless OpenSSH Integration" feature from the [feature matrix](https://goteleport.com/docs/feature-matrix/).

## What It Deploys

- VPC with public + private subnets and a NAT gateway
- `var.node_count` (default: 2) EC2 instances (Amazon Linux 2023)
  - **No Teleport agent installed**
  - Userdata configures sshd to trust Teleport's user CA certificate
  - Creates an OS login (`var.ssh_login`) that Teleport roles can use
- `teleport_server` registrations in your Teleport cluster (`sub_kind = "openssh"`)

## Prerequisites

- A running Teleport cluster (`tsh login` works)
- `eval $(tctl terraform env)` to authenticate Terraform to Teleport
- Your Teleport role must include a login matching `var.ssh_login` (default: `teleport-user`)
  - The demo RBAC roles in `control-plane/*/3-rbac` allow `{{email.local(external.username)}}` — add `teleport-user` as a static login if needed

## Usage

```bash
export TF_VAR_proxy_address="yourcluster.teleport.sh"
export TF_VAR_user="you@example.com"
export TF_VAR_region="us-east-2"

eval $(tctl terraform env)
terraform init
terraform apply
```

Then connect:

```bash
tsh ls                                         # confirm nodes appear (may take ~30s)
tsh ssh teleport-user@agentless-0.dev          # connect to first node
```

## Demo Points

- **No agent install**: `ps aux | grep teleport` returns nothing — Teleport is not running on the host
- **sshd trust**: `cat /etc/ssh/sshd_config.d/teleport-ca.conf` shows the `TrustedUserCAKeys` line pointing to the Teleport CA
- **Full audit**: sessions are recorded and available in the Teleport Web UI even though there's no agent
- **Works for existing infrastructure**: great story for brownfield environments where installing an agent isn't feasible

## EC2 Instance Connect Endpoint (EICE) Upgrade Path

For instances in private subnets (no public IP), Teleport supports agentless access via EC2 Instance Connect Endpoint — no bastion host needed:

1. Set up an [AWS OIDC integration](https://goteleport.com/docs/enroll-resources/application-access/cloud-apis/aws-integration/) in your Teleport cluster
2. Deploy an EC2 Instance Connect Endpoint in the VPC
3. Register nodes with `sub_kind = "openssh-ec2-ice"` and `spec.cloud_metadata.aws` containing `account_id`, `instance_id`, `region`, `vpc_id`, `subnet_id`, and `integration`

```hcl
resource "teleport_server" "eice_node" {
  version  = "v2"
  sub_kind = "openssh-ec2-ice"

  metadata = {
    name   = "${var.account_id}-${aws_instance.node.id}"
    labels = { env = var.env, team = var.team }
  }

  spec = {
    addr     = "${aws_instance.node.private_ip}:22"
    hostname = "agentless-private-0"
    cloud_metadata = {
      aws = {
        account_id  = var.account_id
        instance_id = aws_instance.node.id
        region      = var.region
        vpc_id      = aws_vpc.main.id
        subnet_id   = aws_subnet.private.id
        integration = var.aws_integration_name
      }
    }
  }
}
```

## Inputs

| Variable | Default | Description |
|---|---|---|
| `proxy_address` | required | Teleport proxy hostname |
| `region` | `us-east-2` | AWS region |
| `user` | required | Your email for tagging |
| `env` | `dev` | Environment label |
| `team` | `dev` | Team label |
| `node_count` | `2` | Number of agentless EC2 instances |
| `instance_type` | `t3.micro` | EC2 instance type |
| `ssh_login` | `teleport-user` | OS login created on agentless hosts |

## Outputs

| Output | Description |
|---|---|
| `node_public_ips` | Public IP addresses of the agentless nodes |
| `teleport_node_names` | Teleport node names as registered |
| `connection_guide` | SSH commands to connect |
