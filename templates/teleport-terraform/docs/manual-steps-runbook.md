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

## Okta SCIM Integration and Slack Plugin (moved)

The Okta SCIM setup (API integration + Push Groups) and the Slack plugin bot invite applied only to the EKS control plane, which is no longer part of this repo — the eks control plane (Slack plugin, SCIM, Access Graph) now lives in github.com/tenaciousdlg/teleport-terraform. See that repo's runbook for those steps.

The `control-plane/cloud` and `control-plane/standalone` `3-rbac` layers use static, Terraform-managed access-list membership (set in `terraform.tfvars`) — no SCIM setup is required.

---

## One-Time Setup: GitHub Actions CI Bot

Required only if using the GitHub Actions deploy/teardown workflows. See the full setup guide at [`docs/github-actions-setup.md`](../../../docs/github-actions-setup.md).

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

### Access Lists (cloud / standalone `3-rbac`)

```bash
tsh login --proxy=<cluster>
tctl get access_list                         # members should reflect the tfvars membership lists
```

### GitHub Actions

Actions → **Deploy Teleport Demo** → Run workflow → pick profile `dev-demo`, env `dev`. Profiles are preset tfvars files under `profiles/presets/` applied to the single Terraform root at `profiles/`.

Then verify:
```bash
tsh ls env=dev
```
