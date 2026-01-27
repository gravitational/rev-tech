# Windows Desktop Access (Local Users)

This example provisions a Windows Server host and a Linux Desktop Service on EC2 to demonstrate Teleport Desktop Access for local Windows users.

It mirrors the official [Configure access for local Windows users](https://goteleport.com/docs/enroll-resources/desktop-access/getting-started/) guide and is modularized for reuse.

---

## What It Deploys

- 1 Windows Server 2022 instance
- 1 Linux Desktop Service instance (Teleport `windows_desktop_service`)
- Teleport desktop registration with tier-based labels (e.g., `tier = dev`)
- Shared VPC/subnet/security group baseline

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
export TF_VAR_teleport_version="18.1.6"
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
tsh desktops ls
```

Then connect via the Teleport Web UI or your preferred RDP client through Teleport.

5. Tear down:

```bash
terraform destroy
```

---

## Notes
- This template targets local Windows users, not Active Directory
- Customize labels to align with your desktop RBAC rules
