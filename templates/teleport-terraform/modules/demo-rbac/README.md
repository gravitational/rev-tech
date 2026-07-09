# demo-rbac

Per-profile Teleport RBAC for demo narratives: a dev role, an access-request (JIT) pair, and a local demo user — generated from the profile's own `env`/`team` variables so the role labels always match the resources the profile deploys.

**How it differs from `modules/teleport-rbac`:** that module is the deploy-once, cluster-canonical role set managed from `control-plane/`; its names are fixed and its labels are static. This module is instantiated *per profile*, prefixes every role name with `name_prefix` (so concurrent SEs on one cluster don't collide), and is destroyed with the profile.

## What It Creates

| Resource | Name | Purpose |
|---|---|---|
| `teleport_role` | `<prefix>-dev-access` | Standing access to everything labeled `env=<env>, team=<team>` (SSH, DBs, apps, desktops, MCP) |
| `teleport_role` | `<prefix>-prod-readonly` | Access to `env=<prod_env>` nodes — only via approved access request. Skipped when `prod_env` is null. |
| `teleport_role` | `<prefix>-dev-requester` | Can request `<prefix>-prod-readonly` (max duration = `request_max_duration`, default 1h) |
| `teleport_role` | `<prefix>-prod-reviewer` | Can approve those requests — grant this to the SE (approver persona) |
| `teleport_user` | `bob` (configurable) | Local user holding dev-access + dev-requester: the developer persona |

## Usage

```hcl
module "demo_rbac" {
  source = "../../modules/demo-rbac"

  name_prefix = local.user_prefix   # e.g. "chris"
  env         = var.env             # matches the labels on deployed resources
  prod_env    = var.prod_env        # omit / null to skip the request flow
  team        = var.team
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

The SE approves requests as themselves. That requires holding `<prefix>-prod-reviewer`:

- **Local admin user:** `tctl users update <you> --set-roles=<existing roles>,<prefix>-prod-reviewer`
- **SSO user:** add the role through your connector's `attributes_to_roles` or an access list — SSO role sets can't be edited with `tctl users update`.

## Notes

- Usernames are cluster-global and unprefixed by default (the narrative reads better as `bob`). On a shared demo cluster, set `demo_user_name = "bob-<you>"`.
- `create_demo_user = false` skips the user and creates roles only (e.g. when your IdP provides the personas).
- Destroying the profile removes the roles and the user; any password/MFA device set for the user is deleted with it.
