# GitHub Actions Setup — One-Time Manual Steps

This document covers the infrastructure and configuration that must be set up **once** before the GitHub Actions workflows in `.github/workflows/` will function. None of this is automated by Terraform — it is a prerequisite for the automation.

---

## Overview

The demo deploy/teardown workflows need:
1. AWS credentials (OIDC) — no long-lived keys
2. Teleport credentials (GitHub OIDC join via Machine ID) — no identity files
3. An S3 bucket for Terraform state (enables the scheduled teardown to work)
4. GitHub Actions secrets configured on the repo

---

## 1. AWS — OIDC Identity Provider

**Done once per AWS account.**

In AWS Console → IAM → Identity providers → Add provider:
- Provider type: **OpenID Connect**
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

---

## 2. AWS — IAM Role for GitHub Actions

**Done once.** This role is assumed by the GitHub Actions runner via OIDC.

Create an IAM role with the following trust policy (replace account ID and repo):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Principal": {
        "Federated": "arn:aws:iam::165258854585:oidc-provider/token.actions.githubusercontent.com"
      },
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": ["sts.amazonaws.com"]
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": ["repo:gravitational/rev-tech:*"]
        }
      }
    }
  ]
}
```

**Permissions policies attached to the role:**

| Policy | Purpose |
|---|---|
| `AmazonEC2FullAccess` | EC2 instances, security groups, VPCs |
| `AmazonVPCFullAccess` | VPC/subnet/IGW/NAT creation |
| `AmazonSSMFullAccess` | EC2 autodiscovery (SSM-based installer) |
| `IAMFullAccess` | Instance profiles, IAM roles for EC2 |

Inline policy for S3 state bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::presales-teleport-demo-tfstate",
        "arn:aws:s3:::presales-teleport-demo-tfstate/*"
      ]
    }
  ]
}
```

**Role ARN** (set as `AWS_ROLE_ARN` GitHub secret):
`arn:aws:iam::165258854585:role/<role-name>`

---

## 3. S3 Terraform State Bucket

**Done once.** Required for the scheduled teardown to destroy what the deploy workflow created.

```bash
aws s3 mb s3://presales-teleport-demo-tfstate --region us-east-2
aws s3api put-bucket-versioning \
  --bucket presales-teleport-demo-tfstate \
  --versioning-configuration Status=Enabled
```

Set `TF_STATE_BUCKET = presales-teleport-demo-tfstate` as a GitHub secret.

---

## 4. Teleport — Machine ID Bot and GitHub Join Token

**Done once.** Allows the Terraform provider to authenticate to Teleport using GitHub's OIDC token — no identity file or long-lived credentials needed.

```bash
# Create the bot
tctl bots add github-ci --roles=terraform-provider

# Create the GitHub join token (no secret — GitHub OIDC validates the repo)
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

The token name `github-ci` matches `TF_TELEPORT_JOIN_TOKEN` in the workflow env. No GitHub secret is needed for this — the provider joins using GitHub's built-in OIDC.

---

## 5. GitHub Actions Secrets

Configure at: `github.com/gravitational/rev-tech` → Settings → Secrets and variables → Actions

| Secret | Value | Required |
|---|---|---|
| `AWS_ROLE_ARN` | IAM role ARN from step 2 | yes |
| `TELEPORT_PROXY` | `presales.teleportdemo.com` | yes |
| `TF_STATE_BUCKET` | `presales-teleport-demo-tfstate` | recommended |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL | optional |

---

## 6. Verify

After completing steps 1–5, trigger a test run:

GitHub → Actions → **Deploy Teleport Demo** → Run workflow
- Use case: `server-access-ssh-getting-started`
- Environment: `dev`
- Team: `platform`
- Region: `us-east-2`
- Teleport version: `18.6.4`

Then verify with:
```bash
tsh ls env=dev,team=platform
```

And test teardown:

GitHub → Actions → **Scheduled Demo Teardown** → Run workflow (manual trigger)

---

## Notes

- The Teleport identity join uses GitHub's OIDC token — it is only valid for the duration of the workflow run (no expiry management needed).
- The `terraform-provider` Teleport role is built-in to Teleport Cloud and grants the provider permission to manage all Teleport resources.
- If the bot or token need to be recreated: `tctl bots rm github-ci` then re-run step 4.
- The scheduled teardown runs every Monday at 08:00 UTC and targets the `dev` environment in `us-east-2`.
