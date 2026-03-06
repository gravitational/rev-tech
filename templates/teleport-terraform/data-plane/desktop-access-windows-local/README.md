# Desktop Access — Windows Local Users

Provisions a Windows Server 2022 host and a Linux Desktop Service on EC2 to demonstrate Teleport Desktop Access for local Windows users. Browser-based RDP with no client software, no VPN, and full session recording.

Mirrors the official [Configure access for local Windows users](https://goteleport.com/docs/enroll-resources/desktop-access/getting-started/) guide and is modularized for reuse.

**Tested:** ✅ Confirmed working.

---

## What It Deploys

- 1 Windows Server 2022 instance (t3.medium)
- 1 Linux Desktop Service instance (t3.small) — Teleport `windows_desktop_service`
- Teleport desktop registration with `env`/`team` labels
- Shared VPC/subnet/security group

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_user=you@company.com
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_teleport_version=18.6.4
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

cd data-plane/desktop-access-windows-local
terraform init
terraform apply
```

Or copy the example vars file:

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars, then:
terraform init && terraform apply
```

Allow 4–6 minutes. Windows boot takes longer than Linux. The desktop appears in Teleport once the Desktop Service connects — expect both instances to be fully up.

---

## Access

Desktop Access is **web UI only** — there is no `tsh` command for Windows desktops.

1. Open `https://<proxy>` in a browser
2. Go to **Resources** → filter by **Desktops**
3. Click **Connect**

Alternatively, use the Teleport Connect desktop application.

---

## Demo Points

- **No client software** — browser-based RDP works from any machine with a browser
- **No VPN** — the Desktop Service connects outbound to Teleport; no inbound firewall ports needed
- **No Active Directory** — this template uses local Windows users (not domain-joined)
- **Full session recording** — video + keyboard events captured in the audit log
- **RBAC by labels** — `env` and `team` labels control who sees which desktops

---

## Troubleshooting

If the desktop does not appear in Teleport within 5 minutes:

1. Open the AWS Console → EC2 → select the Desktop Service (Linux) instance → **Actions → Monitor and troubleshoot → Get system log**
2. Look for Teleport installation output at the bottom. It should end with `teleport start` succeeding
3. If you see a TCP connection timeout to the proxy, the security group was not applied — this was a bug in older versions (using `security_groups` instead of `vpc_security_group_ids`). Destroy and redeploy using the current version

---

## Teardown

```bash
terraform destroy
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `user` | Your email — used for tagging and resource naming | **required** |
| `proxy_address` | Teleport proxy hostname | **required** |
| `teleport_version` | Teleport version for the Desktop Service | **required** |
| `env` | Environment label | `"dev"` |
| `team` | Team label | `"platform"` |
| `region` | AWS region | `"us-east-2"` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
