# Manual Steps Runbook

This document covers the steps that cannot be automated by Terraform and must be performed by a human operator. Everything else in this repo is automated.

---

## Every Session (Before Any `terraform apply`)

Teleport provider credentials are short-lived and must be refreshed each session.

```bash
tsh login --proxy=<your-cluster>        # e.g., presales.teleportdemo.com
eval $(tctl terraform env)              # exports TELEPORT_* env vars for the provider
```

`tctl terraform env` creates a temporary bot and returns short-lived credentials. They expire when the shell session ends.

---

## One-Time Setup: Okta SCIM Integration

Required for the `3-rbac` access lists to work. Teleport access lists use SCIM group membership from Okta to drive role assignment.

### Step 1 — Generate SCIM credentials from Teleport

Run this inside the Teleport auth pod (EKS) or directly on the auth node (standalone):

```bash
# EKS
kubectl exec -n teleport-cluster \
  $(kubectl get pod -n teleport-cluster -l app.kubernetes.io/component=auth -o jsonpath='{.items[0].metadata.name}') \
  -- tctl plugins install scim --connector=okta-integrator
```

The output includes four values you will need in the next step:
- **Base URL** (e.g., `https://presales.teleportdemo.com/v1/webapi/scim/okta-integrator`)
- **Token URL**
- **Client ID**
- **Client Secret**

Save these — Teleport will not show the client secret again.

### Step 2 — Configure API Integration in Okta UI

1. Okta Admin → Applications → Teleport app → Provisioning tab
2. Click **Configure API Integration**
3. Select **OAuth 2.0** (not Bearer token)
4. Enter Base URL, Token URL, Client ID, Client Secret from step 1
5. Click **Test API Credentials** → should show a green success indicator
6. Click **Save**

### Step 3 — Configure Push Groups

Push Groups must be added manually — the Okta Terraform provider does not support this resource.

1. Okta Admin → Applications → Teleport app → Push Groups tab
2. Add each of the following groups:
   - `devs`
   - `senior-devs`
   - `engineers`
3. Click **Save**

> The Okta built-in "Everyone" group cannot be pushed via SCIM and is not needed here — access list `everyone` in `3-rbac` uses `type: scim` but relies on any authenticated user.

---

## One-Time Setup: Slack Plugin Bot Invite

Required after deploying `4-plugins` (EKS control plane only).

After `helm upgrade --install` (or `terraform apply` for the plugin layer) succeeds:

1. Open the Slack channel designated for access request notifications
2. Type `/invite @<bot-name>` (the bot name is set in the Helm values for `4-plugins`)
3. Confirm the bot appears as a member of the channel

Access request notifications will not route until the bot is in the channel.

---

## One-Time Setup: GitHub Actions CI Bot

Required only if using the GitHub Actions deploy/teardown workflows. See the full setup guide at [`docs/github-actions-setup.md`](../../docs/github-actions-setup.md).

Summary of what must be done manually:

```bash
# 1. Create the CI bot in Teleport
tctl bots add github-ci --roles=terraform-provider

# 2. Create the GitHub join token (no secret — uses GitHub OIDC)
cat <<EOF | tctl create -f
kind: token
version: v2
metadata:
  name: github-ci
spec:
  roles: [Bot]
  join_method: github
  bot_name: github-ci
  github:
    allow:
      - repository: gravitational/rev-tech
EOF
```

Then configure four secrets in the GitHub repo (Settings → Secrets and variables → Actions):

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role ARN that the runner assumes via AWS OIDC |
| `TELEPORT_PROXY` | Teleport cluster hostname (e.g., `presales.teleportdemo.com`) |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state (enables scheduled teardown) |
| `SLACK_WEBHOOK_URL` | Optional — posts teardown summary to Slack |

---

## Verification

After completing setup, verify each integration:

### Teleport + Okta SCIM

```bash
tsh login --proxy=<cluster>
tsh status                                   # confirms auth connector is okta-integrator
tctl get access_list                         # lists access lists; members should reflect Okta groups
```

### Slack Plugin

Submit a test access request and confirm a notification appears in the channel:

```bash
tsh request create --roles=prod-readonly-access --reason="runbook test"
```

### GitHub Actions

Actions → **Deploy Teleport Demo** → Run workflow → pick `server-access-ssh-getting-started`, env `dev`.

Then verify:
```bash
tsh ls env=dev
```
