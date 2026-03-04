# 4-plugins — Teleport Slack Access Request Plugin

Deploys the [Teleport Slack plugin](https://goteleport.com/docs/access-controls/access-request-plugins/ssh-approval-slack/) into the EKS cluster. When a user creates a Teleport access request, the plugin posts an interactive approval card to a Slack channel. Reviewers click **Approve** or **Deny** directly in Slack.

## Prerequisites

- Layers 1-cluster, 2-teleport, and 3-rbac must be applied.
- A Slack app with:
  - **Bot Token Scopes**: `chat:write`, `users:read`, `users:read.email`
  - **Interactivity** enabled (request URL: `https://<proxy>:443/slack/actions`)

## Deploy

```bash
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_slack_bot_token=xoxb-...
export TF_VAR_slack_signing_secret=abc123...
export TF_VAR_slack_channel_id=C01234ABCDE
terraform init && terraform apply
```

## Bootstrap (one-time after first apply)

The plugin authenticates to Teleport using an identity file. Generate it once:

```bash
# 1. Sign a long-lived identity for the plugin service account
tctl auth sign --format=file \
  --user=slack-plugin-service \
  --out=plugin-identity \
  --ttl=8760h   # 1 year; rotate annually

# 2. Upload the identity file as a Kubernetes secret
kubectl create secret generic teleport-plugin-slack-identity \
  --from-file=auth_id=plugin-identity \
  -n teleport-plugins

# 3. Restart the plugin to load the secret
kubectl rollout restart deployment/teleport-plugin-slack -n teleport-plugins

# Verify
kubectl get pods -n teleport-plugins
kubectl logs -n teleport-plugins -l app.kubernetes.io/name=teleport-plugin-slack
```

## Demo Flow

### Request side (user with `dev-requester` role)

```bash
tsh login --proxy=myorg.teleport.sh:443

# Request prod-readonly access for a time-boxed incident investigation
tsh request create \
  --roles=prod-readonly-access \
  --reason="Investigating prod latency spike (INC-4231)" \
  --max-duration=4h

# Watch the request status
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

# Now has prod-readonly access for up to 4h
tsh ssh ec2-user@<prod-node>
tsh db connect rds-mysql-prod

# Role drops automatically after max-duration or on logout
tsh logout
```

## RBAC model (from 3-rbac)

| Role | Can request | Can review |
|------|-------------|------------|
| `dev-requester` | `platform-dev-access`, `prod-readonly-access`, `prod-access` | — |
| `prod-requester` | `prod-readonly-access`, `prod-access` | — |
| `dev-reviewer` | — | `dev-access`, `platform-dev-access` |
| `prod-reviewer` | — | `prod-readonly-access`, `prod-access` |

Engineers access list receives: `platform-dev-access`, `dev-reviewer`, `prod-requester`, `prod-reviewer`.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `proxy_address` | Teleport proxy hostname | required |
| `region` | AWS region | `us-east-2` |
| `teleport_namespace` | Namespace where Teleport is installed | `teleport-cluster` |
| `plugin_namespace` | Namespace for the Slack plugin | `teleport-plugins` |
| `slack_bot_token` | Slack Bot User OAuth Token (`xoxb-...`) | required |
| `slack_signing_secret` | Slack app signing secret | required |
| `slack_channel_id` | Slack channel ID for notifications | required |
| `plugin_chart_version` | Helm chart version (empty = latest) | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `plugin_service_user` | Teleport user name for the plugin |
| `plugin_namespace` | Kubernetes namespace |
| `bootstrap_commands` | Full bootstrap and demo flow reference |
