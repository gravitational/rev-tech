# demo-rbac

Per-profile Teleport RBAC for demo narratives: a dev role, a requestable JIT role trio (staging / prod / prod-with-MFA), the requester/reviewer pair, an optional policy auto-approval rule, and a local demo user — generated from the profile's own `env`/`team` variables so the role labels always match the resources the profile deploys.

**How it differs from `modules/teleport-rbac`:** that module is the deploy-once, cluster-canonical role set managed from `control-plane/`; its names are fixed and its labels are static. This module is instantiated *per profile*, prefixes every role name with `name_prefix` (so concurrent SEs on one cluster don't collide), and is destroyed with the profile. On a dedicated cluster (e.g. an event environment), set `name_prefix = ""` for the canonical unprefixed names the published demo docs use.

## What It Creates

| Resource | Name | Purpose |
|---|---|---|
| `teleport_role` | `<prefix>-dev-access` | Standing access to everything labeled `env=<env>, team=<team>` (SSH, DBs, apps, desktops, MCP) |
| `teleport_role` | `<prefix>-staging-access` | Requestable elevation over the `env=<env>` resources — the auto-approve target. Skipped when `prod_env` is null. |
| `teleport_role` | `<prefix>-prod-access` | Access to `env=<prod_env>` nodes — only via approved access request. Skipped when `prod_env` is null. |
| `teleport_role` | `<prefix>-prod-access-mfa` | Same as prod-access plus per-session MFA (`require_session_mfa = 1`, webauthn). Skipped when `prod_env` is null. |
| `teleport_role` | `<prefix>-requester` | Can request the trio above (max duration = `request_max_duration`, default 1h). Named `demo-requester` when unprefixed (the `requester` preset exists). |
| `teleport_role` | `<prefix>-reviewer` | Can approve those requests — grant this to the SE (approver persona). Named `demo-reviewer` when unprefixed. |
| `teleport_access_monitoring_rule` | `<prefix>-auto-approve-staging` | Auto-approves staging-access requests whose reason contains `auto_approve_reason` (builtin integration). Created only when `auto_approve_reason` is set. |
| `teleport_user` | `bob` (configurable) | Local user holding dev-access + requester: the developer persona |

## Usage

```hcl
module "demo_rbac" {
  source = "../../modules/demo-rbac"

  name_prefix = local.user_prefix   # e.g. "chris"; "" = canonical unprefixed names
  env         = var.env             # matches the labels on deployed resources
  prod_env    = var.prod_env        # omit / null to skip the request flow
  team        = var.team

  auto_approve_reason = "authorized job" # optional: policy-approve staging requests
}
```

## Activating the Demo User

Terraform creates the user but cannot set credentials:

```bash
tctl users reset bob        # prints a one-time reset link — set password + MFA
tsh login --proxy=<proxy>:443 --user=bob --auth=local
```

`--auth=local` matters on clusters where SSO is the default connector.

## The Approver Side

Staging requests approve themselves when `auto_approve_reason` is set. Prod requests need a human: the SE approves as themselves, which requires holding `<prefix>-reviewer` (`demo-reviewer` when unprefixed):

- **Local admin user:** `tctl users update <you> --set-roles=<existing roles>,<prefix>-reviewer`
- **SSO user:** add the role through your connector's `attributes_to_roles` or an access list — SSO role sets can't be edited with `tctl users update`.

## Notes

- Usernames are cluster-global and unprefixed by default (the narrative reads better as `bob`). On a shared demo cluster, set `demo_user_name = "bob-<you>"`.
- `create_demo_user = false` skips the user and creates roles only (e.g. when your IdP provides the personas).
- Destroying the profile removes the roles and the user; any password/MFA device set for the user is deleted with it.
