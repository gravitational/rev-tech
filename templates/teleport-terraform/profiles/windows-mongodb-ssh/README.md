# Profile: windows-mongodb-ssh — Traditional Enterprise

**Archetype:** Financial services, healthcare, and legacy enterprise shops running Windows desktops, MongoDB, and Linux SSH servers.

Use this when the prospect has not moved fully to cloud-native and wants to see Teleport handle the "old stack" — Windows, MongoDB, Linux servers — without requiring AD or a VPN.

**Cost:** ~$2–4/day.

---

## What It Deploys

| Resource | Count | Type | Purpose |
|---|---|---|---|
| SSH nodes | 2 | t3.micro | Server Access — Linux SSH |
| MongoDB (self-hosted) | 1 | t3.small | Database Access — TLS cert auth |
| Windows Server | 1 | t3.medium | Desktop Access target |
| Desktop Service | 1 | t3.small | Linux RDP proxy |
| NAT Gateway | 1 | — | ~$1.20/day fixed |

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com
export TF_VAR_teleport_version=18.6.4
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

cd profiles/windows-mongodb-ssh
terraform init
terraform apply
```

Allow 4–6 minutes for all instances to boot and register (Windows takes longer).

---

## Verify

```bash
tsh ls env=dev,team=platform        # dev-ssh-0, dev-ssh-1
tsh db ls env=dev,team=platform     # mongodb-dev
# Desktops: web UI only — https://<proxy> → Windows Desktops
```

---

## Key Demo Commands

### Server Access — SSH

```bash
tsh ls env=dev,team=platform
tsh ssh ec2-user@dev-ssh-0

# In session — point out:
# - Teleport created the host user dynamically (no pre-provisioning)
# - Session is being recorded
# - w / who shows the Teleport audit user
```

### Database Access — MongoDB

```bash
# Connect as reader
tsh db login mongodb-dev --db-user=reader
tsh db connect mongodb-dev
# mongosh prompt — connected via short-lived cert, no password

# Connect as writer
tsh db login mongodb-dev --db-user=writer
tsh db connect mongodb-dev
```

MongoDB is configured with Teleport's custom CA. The Teleport DB agent issues a short-lived client cert for each connection — no passwords exist anywhere in the chain.

### Desktop Access — Windows

Web UI only. Open `https://<proxy>` → **Windows Desktops** → click **Connect**.

- Browser-based RDP — no client software required
- Full session recording (video + events)
- No VPN needed
- Works with local Windows users (no Active Directory required)

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
| `user` | Your email — used for tagging and resource naming | **required** |
| `teleport_version` | Teleport version | **required** |
| `env` | Environment label | `"dev"` |
| `team` | Team label | `"platform"` |
| `region` | AWS region | `"us-east-2"` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
