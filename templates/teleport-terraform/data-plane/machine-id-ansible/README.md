# Machine ID — Ansible Automation

Deploys an EC2 host running Ansible and tbot (Teleport Machine ID), configured to run Ansible playbooks against Teleport-enrolled nodes using short-lived bot certificates — no SSH keys required.

**Use case:** Show how CI/CD and automation tools authenticate to infrastructure through Teleport without long-lived credentials.

Mirrors the official [Machine ID with Ansible](https://goteleport.com/docs/enroll-resources/machine-id/access-guides/ansible/) guide.

---

## What It Deploys

- 1 EC2 instance running Ansible and tbot
- Machine ID bot with role scoped to nodes matching `env` + `team` labels
- Teleport SSH service on the host for management
- Sample Ansible inventory and playbook at `/home/ec2-user/ansible/`

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

cd data-plane/machine-id-ansible
terraform init
terraform apply
```

Allow 3–5 minutes for the instance to boot, tbot to start, and the host to register.

---

## Access

```bash
tsh ls env=dev,team=platform            # find the ansible host
tsh ssh ec2-user@<ansible-host>
```

Once on the host, build your inventory from live Teleport node names and run the playbook:

```bash
# Build inventory from enrolled nodes
tsh ls env=dev --format=json | jq -r '.[].spec.hostname' > ~/ansible/hosts

# Run the playbook — Ansible uses tbot certificates, no SSH keys
cd ~/ansible
ansible-playbook -i hosts playbook.yaml
```

---

## Demo Points

- **No SSH keys** — tbot fetches short-lived certificates from Teleport on every run; Ansible never holds a long-lived credential
- **Bot-scoped access** — the bot role only permits access to nodes matching the `env`/`team` labels; it cannot reach anything outside that scope
- **Full audit trail** — every Ansible-initiated SSH session is recorded in Teleport's audit log with the bot identity, not a generic service account
- **Revocable** — removing the bot from the role immediately blocks all further Ansible runs

---

## Teardown

```bash
terraform destroy
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `user` | Your email — used for tagging | **required** |
| `proxy_address` | Teleport proxy hostname | **required** |
| `teleport_version` | Teleport version to install | **required** |
| `env` | Environment label | **required** |
| `team` | Team label | `"platform"` |
| `region` | AWS region | **required** |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |

---

## Notes

- Bot names are generated as `ansible-<4-char-suffix>` to avoid backend collisions across destroy/apply cycles
- The host uses **bound keypair preregistered key** onboarding (`initial_public_key`) with recovery mode `insecure` for demo reliability
- tbot writes SSH config to `/opt/machine-id/ssh_config`
