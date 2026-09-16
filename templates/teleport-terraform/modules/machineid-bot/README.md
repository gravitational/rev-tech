# Machine ID Bot Module

Creates a Teleport Machine ID bot, bound keypair provision token, and role for automated access.

## Usage

```hcl
module "machineid_bot" {
  source = "../../modules/machineid-bot"

  bot_name       = "ansible"
  role_name      = "ansible-machine-role"
  allowed_logins = ["ec2-user", "engineer"]
  node_labels = {
    env = ["dev"]
    team = ["platform"]
  }
  app_labels = {
    env = ["dev"]
    "teleport.internal/app-sub-kind" = ["mcp"]
  }
  mcp_tools = ["*"]
}
```

## Inputs

| Variable | Description | Type | Default |
| -------- | ----------- | ---- | ------- |
| `bot_name` | Machine ID bot name | `string` | - |
| `role_name` | Teleport role name | `string` | - |
| `allowed_logins` | Allowed system logins | `list(string)` | `[]` |
| `node_labels` | Node label access map | `map(list(string))` | `{}` |
| `app_labels` | App label access map | `map(list(string))` | `{}` |
| `mcp_tools` | MCP tool allow list | `list(string)` | `[]` |
| `onboarding_initial_public_key` | Optional preregistered SSH public key for onboarding | `string` | `""` |
| `bound_keypair_recovery_mode` | Bound keypair recovery mode (`standard`, `relaxed`, `insecure`) | `string` | `"standard"` |
| `bound_keypair_recovery_limit` | Bound keypair recovery rejoin limit | `number` | `10` |

## Outputs

| Output | Description |
| ------ | ----------- |
| `bot_token` | Provision token name for the bot |
| `bot_registration_secret` | Generated registration secret from token status |
| `bot_name` | Bot name |
| `role_id` | Role ID |

## MCP Example Role

```yaml
allow:
  app_labels:
    env: ["dev"]
    teleport.internal/app-sub-kind: ["mcp"]
  mcp:
    tools: ["*"]
```

## References

- [Machine ID deployment guide](https://goteleport.com/docs/machine-workload-identity/deployment/)
- [Machine ID with Ansible](https://goteleport.com/docs/machine-workload-identity/access-guides/ansible/)
- [Machine ID with MCP](https://goteleport.com/docs/machine-workload-identity/access-guides/mcp/)

Note: this module uses `bound_keypair` join and supports either generated registration secrets or preregistered keys (`onboarding_initial_public_key`).

## Operational notes — bound keypair tokens

- **The registration secret is a one-time bootstrap credential.** The
  `bot_registration_secret` output is marked `sensitive`, so it won't appear
  in `terraform apply` output or CI logs. Retrieve it deliberately:
  `terraform output -raw bot_registration_secret`. It still exists in the
  Terraform state — protect the state backend accordingly. After the bot's
  first join the secret is spent and worthless to an attacker.
- **Changing the token re-arms onboarding and breaks the live binding.**
  Updating a bound-keypair token's spec (for example bumping the recovery
  limit) causes the backend to re-arm onboarding from the spec — the bot's
  existing keypair binding is invalidated and its next join fails with
  "a valid registration secret is required". Plan any token change as a
  rebind: apply the change, retrieve the fresh registration secret, wipe the
  bot's local state, and let it re-join. (Observed in the field Aug 2026 via
  the Kubernetes operator's reconcile of an unrelated field; the same upsert
  semantics apply to Terraform updates.)
- **Recovery mode `standard` with a finite limit is the default on purpose.**
  Every rejoin after the bot's identity expires consumes one recovery. Size
  `bound_keypair_recovery_limit` to the bot's restart cadence — a bot that
  cold-starts daily burns ~30/month. `insecure` disables the binding
  protections and is for lab use only.
