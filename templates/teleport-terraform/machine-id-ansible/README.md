# Machine ID + Ansible Automation

This example provisions an EC2 host with Teleport Machine ID (tbot) and Ansible configured for automated workflows using bot identity.

It mirrors the official [Machine ID with Ansible](https://goteleport.com/docs/enroll-resources/machine-id/access-guides/ansible/) guide and is modularized for reuse.

---

## What It Deploys

- 1 EC2 instance running Ansible and tbot
- Teleport bot identity and role for machine automation
- Teleport SSH service on the host for management

---

## Usage

1. Authenticate to your Teleport cluster:

```bash
tsh login --proxy=teleport.example.com --auth=example
eval $(tctl terraform env)
```

2. Set variables (preferred) or use a tfvars file:

```bash
export TF_VAR_user="engineer@example.com"
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_teleport_version="18.6.4"
export TF_VAR_region="us-east-2"
export TF_VAR_env="dev"
```

Or:

```bash
cp terraform.tfvars.example terraform.tfvars
```

3. Deploy:

```bash
terraform init
terraform apply
```

4. Access:

```bash
tsh ls --labels=tier=dev
tsh ssh ec2-user@<ansible-host>
```

5. Tear down:

```bash
terraform destroy
```

---

## Notes
- Bot permissions are scoped by labels (tier/team)
- The host contains `/opt/machine-id/ssh_config` for bot-based SSH
