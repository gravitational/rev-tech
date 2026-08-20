# Teleport-side resources

`../setup.sh` renders the `tctl`-applied files below from `${VAR}`
placeholders (values come from `../.env`) and applies them for you. This
file documents what it does and why, for anyone applying them by hand or
auditing what the script does.

| File | Resource | Applied when | Purpose |
|---|---|---|---|
| `workload_identity.yaml` | `kind: workload_identity` | always | The SPIFFE identity issued to Postgres clients, whether via tbot or a human's own `tsh workload-identity issue-x509`; CN pins the Postgres role it authenticates as. |
| `role-tbot.yaml` | `kind: role` | always | Grants the bot permission to issue that identity and reach the Postgres app. |
| `bot.yaml` | `kind: bot` | always | The Machine ID bot identity tbot joins as. |
| `token.yaml` | *(reference only, not applied)* | -- | Explains the dynamically-generated `kind: token` resources `setup.sh`'s `generate_join_token` creates instead -- see that file. |
| `role-human-cli.yaml` | `kind: role` | always | Lets a human `tsh` user self-issue the Workload Identity and reach the Postgres app -- see `../clients/cli/README.md`. |
| `role-db-access.yaml` | `kind: role` | `ENABLE_DB_SERVICE=true` | Grants plain Teleport Database Access to "demo" with automatic Postgres user provisioning. |
| `app-service-teleport-config.yaml` | *(reference only, not rendered by setup.sh)* | -- | A real `teleport.yaml` `app_service` block, for the `DEPLOY_TELEPORT_AGENT=false` manual-merge path. |
| `db-service-teleport-config.yaml` | *(reference only, not rendered by setup.sh)* | -- | Same, for `db_service`. |

`setup.sh` deploys its own Teleport agent (the official
`teleport-kube-agent` chart, release name `$TELEPORT_AGENT_RELEASE`,
joining with its own `app,db`-scoped token) by registering Postgres
directly through that chart's own top-level `apps:`/`databases:` values
-- **not** by rendering the two `*-teleport-config.yaml` files above.
Those exist purely for the `DEPLOY_TELEPORT_AGENT=false` path, where you
merge them into a real `teleport.yaml` for an agent you already run
elsewhere. This split exists because the teleport-kube-agent chart
validates whether an "application source" is configured by inspecting
its own `apps:`/`databases:` values directly -- handing it the
equivalent `app_service:`/`db_service:` block nested inside its
`teleportConfig:` passthrough instead fails with "app service is
enabled, but no application source is enabled" (caught by actually
dry-running `setup.sh` against a live cluster, not obvious from the
chart's docs alone).

## Two access paths, why both exist

- **Workload Identity + TCP Application Access** (`workload_identity.yaml`,
  `role-tbot.yaml`, `bot.yaml`, `role-human-cli.yaml`, plus the agent's
  `apps:` entry): the point of this demo. Clients authenticate to
  Postgres directly with a SPIFFE X.509-SVID; Teleport only provides the
  network path.
- **Plain Teleport Database Access with auto-user-provisioning**
  (`role-db-access.yaml`, plus the agent's `databases:` entry): optional,
  `ENABLE_DB_SERVICE` in `../.env` (default `true`). Shows the more
  common Teleport Database Access pattern for comparison -- a human runs
  `tsh db connect` and gets their own Postgres login auto-created on the
  fly (named after their Teleport username, granted the `reader`/`writer`
  privilege groups from `../postgres-chart/values.yaml`'s
  `03-teleport-db-service.sql`) instead of everyone sharing "app_user".
  Set `ENABLE_DB_SERVICE=false` and re-run `../setup.sh` to remove this
  path entirely: `role-db-access` and the `db-client-ca` Secret are
  removed, `postgres-chart`'s `databaseAccess.enabled` is set to `false`
  (so it stops requiring that secret), and the agent is redeployed
  without a `databases:` entry.

## Why tbot joins with the plain `token` method, not `kubernetes`

Simpler to operate for a demo -- no in-cluster TokenReview wiring to get
right -- at the cost of `setup.sh` having to mint and hand tbot a
bootstrap secret itself (see `token.yaml`'s comments). tbot only needs
that token for its very first join; `tbot-chart`'s `storage.type:
directory` + PVC persist its own bot certificate across restarts so it
never needs the token again. This is also why `workload_identity.yaml`'s
`rules.allow` is left unconditional -- the plain `token` method doesn't
produce the rich per-caller attributes a `kubernetes`/`iam`/etc. join
would, so RBAC (which role is assigned to whom) is the real access
control here, not a resource-level condition.

## Before you apply these by hand

Update every occurrence of (all come from `../.env`, see `../.env.example`):

- `${NAMESPACE}` -- the namespace `../postgres-chart` and
  `../tbot-chart` are installed into.
- `${BOT_NAME}` -- the tbot ServiceAccount name (matches
  `../tbot-chart`'s `fullnameOverride`).
- `${WORKLOAD_IDENTITY_NAME}`, `${POSTGRES_DB_USER}`, `${CLI_ROLE_NAME}`,
  `${APP_NAME}` -- as named.
- `${TELEPORT_PROXY_ADDR}` -- your cluster's proxy address.

## What's actually been confirmed

Everything in this directory has been applied for real against a live
Teleport cluster and run end-to-end, not just rendered: every resource
here via `tctl create -f`, `generate_join_token`'s `kind: token`
resources, the full `teleport-kube-agent` deployment (joined, heartbeat
confirmed via `kubectl logs`), `tbot-chart` (joined using a
`generate_join_token`-created token, issued a real SVID), and a real
Postgres transaction from both the Python and Go clients authenticating
purely via that SVID. See `../README.md`'s "What's been verified"
section for the specific bugs that live testing caught along the way
(most only surface once real pods run, not from `--dry-run` or code
review).

What's genuinely still unverified: this was tested against one specific
Teleport cluster version (18.10.4) and one Kubernetes distribution (EKS,
via the shared `tele1c` cluster). Teleport's Workload Identity,
join-method, and Database Access APIs have changed field names across
releases, so if you're on a meaningfully different Teleport version,
re-verify field names the same way this was verified: apply each
resource for real (`tctl create -f`) rather than trusting the YAML as
written, and run `tctl get <kind>/<name>` afterward to see it as your
cluster's Auth Service actually stored it -- the fastest way to catch a
stale field name.
