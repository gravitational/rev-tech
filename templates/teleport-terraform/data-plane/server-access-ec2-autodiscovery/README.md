# Server Access — EC2 Auto-Discovery

Demonstrates Teleport's EC2 auto-discovery using SSM + IAM joining. A Discovery Service agent scans AWS for tagged EC2 instances and automatically installs Teleport on them — no manual token passing, no pre-baked AMIs, no `user_data` Teleport config on the targets.

**Key story:** Tag an instance, it shows up in Teleport within ~60 seconds. Remove the tag, it's gone. Zero touch on the EC2 side.

---

## What It Deploys

- 1 EC2 instance running Teleport `discovery_service` + `ssh_service` (the agent registers as both a Discovery agent and an SSH node itself)
- N bare Amazon Linux 2023 instances (default 2) — no Teleport pre-installed
- IAM role for targets with `AmazonSSMManagedInstanceCore` (SSM agent receives installer)
- IAM join token (no secret — targets authenticate via their instance IAM role)
- Shared VPC/subnet/security group

---

## How It Works

1. Terraform creates target EC2 instances tagged with `env=dev` (default discovery filter)
2. The Discovery agent finds tagged instances via the AWS API (~30 second poll interval)
3. The agent sends the Teleport installer script to each target via SSM
4. Targets install Teleport and join the cluster using IAM joining — no token secret needed
5. Nodes appear in `tsh ls` within ~60 seconds of the tag being applied

All AWS EC2 tags are automatically surfaced as Teleport node labels, enabling label-based RBAC without any additional configuration.

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_user=you@company.com
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_teleport_version=18.7.1
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

cd data-plane/server-access-ec2-autodiscovery
terraform init
terraform apply
```

Allow ~2 minutes for the discovery agent to boot and ~60 seconds more for targets to enroll.

---

## Verify

```bash
tsh ls                              # target nodes appear with EC2 tags as labels
tsh ls env=dev                      # filter by tag-derived label
```

---

## Demo: Live Tag-Based Enrollment

To show live enrollment during a demo:

1. Deploy without target instances (`TF_VAR_target_count=0`)
2. During the demo, create an EC2 instance in the console with the discovery tag
3. Watch it appear in `tsh ls` within ~60 seconds

Or use the AWS CLI:

```bash
# Tag an existing instance with the discovery key/value (default: env=dev)
aws ec2 create-tags \
  --resources i-0123456789abcdef0 \
  --tags Key=env,Value=dev

# Watch it enroll
watch -n 5 tsh ls
```

---

## Teardown

```bash
terraform destroy
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `proxy_address` | Teleport proxy hostname | **required** |
| `user` | Your email — used for tagging | **required** |
| `teleport_version` | Teleport version for the discovery agent | **required** |
| `env` | Environment label | `"dev"` |
| `team` | Team label | `"platform"` |
| `region` | AWS region (must match where target instances run) | `"us-east-2"` |
| `target_count` | Number of bare EC2 instances to create as targets | `2` |
| `ec2_tag_key` | AWS tag key used to select instances for discovery | `"env"` |
| `ec2_tag_value` | AWS tag value used to select instances for discovery | `"dev"` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
