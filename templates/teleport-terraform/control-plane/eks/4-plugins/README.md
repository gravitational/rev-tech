# 4-plugins — Teleport Slack Access Request Plugin

Deploys the [Teleport Slack plugin](https://goteleport.com/docs/access-controls/access-request-plugins/ssh-approval-slack/) into the EKS cluster. When a user creates a Teleport access request, the plugin posts an interactive approval card to a Slack channel. Reviewers click **Approve** or **Deny** directly in Slack.

## Prerequisites

- Layers 1-cluster, 2-teleport, and 3-rbac must be applied.
- A Slack app with:
  - **Bot Token Scopes**: `chat:write`, `users:read`, `users:read.email`
  - Bot invited to the notification channel: `/invite @<bot>`

## Deploy

```bash
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_slack_bot_token=xoxb-...
export TF_VAR_slack_channel_id=C01234ABCDE
terraform init && terraform apply
```

No manual bootstrap required. Terraform creates a `TeleportBotV1` (Machine ID) and a kubernetes join `TeleportProvisionToken`. The Helm chart's built-in tbot sidecar authenticates to Teleport using the pod's ServiceAccount JWT and continuously renews credentials automatically.

## Verify

```bash
# tbot (credential renewal) logs
kubectl logs -n teleport-plugins \
  -l app=tbot-slack-plugin --tail=50

# Plugin logs
kubectl logs -n teleport-plugins \
  -l app.kubernetes.io/name=teleport-plugin-slack --tail=50
```

## Demo Flow

### Request side

```bash
tsh login --proxy=myorg.teleport.sh:443

# Bob (dev-requester): can only request prod-readonly-access
tsh request create \
  --roles=prod-readonly-access \
  --reason="Investigating prod latency spike (INC-4231)"

# Alice (senior-dev-requester): can also request prod-access / prod-auto-access
tsh request create \
  --roles=prod-access \
  --reason="Hotfix deployment needs prod DB access"

# Watch request status
tsh request ls
```

### Approval side (engineer with `prod-reviewer` role)

The Slack card appears in the configured channel. Click **Approve** or **Deny**.

Alternatively from the CLI:

```bash
tsh request review --approve --reason="Confirmed incident, approved" <request-id>
```

### After approval

```bash
# Activate the elevated role
tsh login --request-id=<request-id>

# Now has prod access for up to the approved duration
tsh ssh ec2-user@<prod-node>
tsh db connect rds-mysql-prod

# Role drops automatically after max-duration or on logout
tsh logout
```

## RBAC model (from 3-rbac)

| Role | Can request | Can review |
|------|-------------|------------|
| `dev-requester` | `prod-readonly-access` | — |
| `senior-dev-requester` | `prod-readonly-access`, `prod-access`, `prod-auto-access` | — |
| `prod-requester` | `prod-readonly-access`, `prod-access`, `prod-auto-access` | — |
| `dev-reviewer` | — | `dev-access`, `platform-dev-access` |
| `prod-reviewer` | — | `prod-readonly-access`, `prod-access`, `prod-auto-access` |

Access list grants:
- `devs`: `dev-requester`
- `senior-devs`: `senior-dev-requester`
- `engineers`: `prod-requester`, `prod-reviewer`, `dev-reviewer`

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `proxy_address` | Teleport proxy hostname | required |
| `region` | AWS region | `us-east-2` |
| `teleport_namespace` | Namespace where Teleport is installed | `teleport-cluster` |
| `plugin_namespace` | Namespace for the Slack plugin | `teleport-plugins` |
| `slack_bot_token` | Slack Bot User OAuth Token (`xoxb-...`) | required |
| `slack_channel_id` | Slack channel ID for notifications | required |
| `plugin_chart_version` | Helm chart version (empty = latest) | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `plugin_namespace` | Kubernetes namespace |
| `tbot_status` | Commands to verify tbot and plugin health, plus demo flow reference |
