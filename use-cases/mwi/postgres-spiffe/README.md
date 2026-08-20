# Postgres + Teleport Workload Identity demo

An example [Teleport Workload
Identity](https://goteleport.com/docs/machine-workload-identity/workload-identity/)
use case: giving scheduled jobs -- Kubernetes CronJobs here, but the
same pattern applies to a CI/CD pipeline or any other non-human
workload -- secure access to a database, with no shared password to
provision, rotate, or leak. Teleport Workload Identity securely issues
short-lived cryptographic identities to workloads and non-human
identities using the open [SPIFFE](https://goteleport.com/docs/enroll-resources/workload-identity/spiffe/)
standard, so a workload can authenticate to another service -- here,
Postgres -- without a long-lived shared secret.

Concretely: Postgres authenticates every client with mutual TLS, using
a SPIFFE X.509-SVID issued by Teleport Workload Identity as the client
certificate. **The Python and Go CronJobs connect straight to
Postgres' Kubernetes Service, with no Teleport proxy in that
connection at all** -- once a workload holds its SVID, Teleport's job
is done; it doesn't need to stay in the network path the way Teleport
Application Access does. That's the point being demonstrated: these
jobs already run inside the cluster and have a real network route to
Postgres, so the SVID alone is enough. The CLI walkthrough shows the
other side of that same trust relationship from a human's workstation,
which *isn't* already on that network -- so it goes through Teleport
TCP Application Access (`tsh vnet`) to reach Postgres, presenting the
same kind of SVID as its client certificate once there. A second,
optional path (`ENABLE_DB_SERVICE`) shows plain Teleport Database
Access with automatic Postgres user provisioning, for comparison --
there, Teleport's Database Service does the authenticating on your
behalf, and you never touch a certificate.

**Quickstart:** `cp .env.example .env`, fill in `TELEPORT_PROXY_ADDR`,
`tsh login`, then `./setup.sh`. See "Deploying" below for what it does
and what to check afterward.

**Prerequisite: your own Teleport user needs Workload Identity
permissions, or `setup.sh` will fail partway through.** Step 2 of
`setup.sh` self-issues a Workload Identity credential using *your own*
`tsh` session (to seed the trust bundle Postgres trusts) -- if your
user's roles don't grant `read`/`list` on `workload_identity` resources,
that step dies with `Could not self-issue the Workload Identity`. This
isn't guaranteed by common presets like `access` or `editor` -- check
with `tsh status` (look for a role that grants Workload Identity access)
before assuming you're covered. If you're not, create and assign this
role once per cluster:

```yaml
# workload-identity-self-issuer.yaml
kind: role
version: v7
metadata:
  name: workload-identity-self-issuer
spec:
  allow:
    workload_identity_labels:
      '*': ['*']
    rules:
      - resources: [workload_identity]
        verbs: [read, list]
```

```bash
tctl create -f workload-identity-self-issuer.yaml
tctl users update <you> --set-roles=<your-existing-roles>,workload-identity-self-issuer
```

It's intentionally broad (`'*': ['*']`) since the demo's own
`$DEMO_LABEL_VALUE` label doesn't exist until `.env` is generated on
first run -- there's no way to scope it tighter ahead of time. Once
`setup.sh` has run and created the narrower `$CLI_ROLE_NAME` role (see
"Two ways to reach Postgres" below), you can swap to that instead and
drop this broader one, if you'd rather keep access scoped to just this
demo.

## How the pieces fit together

Two separate network paths reach the same Postgres, depending on
whether the connecting workload already has a route to it:

```
Jobs (already inside the cluster) -- Teleport issues the credential,
then gets out of the way; no Teleport proxy in the connection itself:

  Teleport cluster                    tbot-chart
  workload_identity, role-tbot, bot   (Deployment, 1 replica)
       │ joins (`token` method)            workload-identity-x509
       │ issues SVID ─────────────────▶      → Secret "postgres-wi-svid"
                                                     │ mounted by
                                                     ▼
                                       clients/python/chart, clients/go/chart
                                                     │
                                                     │ direct mTLS connection
                                                     │ (SVID as client cert) --
                                                     │ Teleport is NOT in this
                                                     │ network path at all
                                                     ▼
                                       postgres-chart (bitnami/postgresql)
                                       ssl_ca_file = Workload Identity bundle
                                       (+ db_client CA if ENABLE_DB_SERVICE=true)

A human's workstation (NOT already inside the cluster) -- still needs
Teleport as the network path, same as any other Application Access:

  Teleport cluster                    clients/cli (tsh)
  role-human-cli, role-db-access           │
       │ issues SVID ──────────────────────┤ tsh workload-identity issue-x509
                                            │
                                            ▼
                                       tsh vnet  (Teleport TCP Application Access)
                                       -- or --  tsh db connect (Database Access)
                                            │
                                            ▼
                                       teleport-agent (teleport-kube-agent)
                                       app_service: "postgres", db_service (optional)
                                            │ proxies tcp://postgres:5432
                                            ▼
                                       postgres-chart
```

Two independent trust relationships, both TLS, running over the same
connection:

- **Client → Postgres server**: Postgres presents a self-signed cert
  that `postgres-chart` generates for itself; clients verify it against
  that chart's `postgres-server-ca` Secret.
- **Postgres → client**: clients present a SPIFFE X.509-SVID from
  Teleport Workload Identity as their client cert; Postgres verifies it
  against `ssl_ca_file`, populated from your Teleport cluster's Workload
  Identity trust bundle (plus Teleport's `db_client` CA too, if
  `ENABLE_DB_SERVICE=true`). Postgres' `cert` auth method then maps the
  connecting username to the certificate's CN, which is why the
  `workload_identity` resource pins `common_name: app_user`.

See [CERTIFICATES.md](CERTIFICATES.md) for the full walkthrough of both
trust relationships above -- which files generate which CA/cert, how
`pg_hba.conf` turns a valid client certificate into a specific Postgres
login, and how the optional Database Access path (below) fits into the
same `ssl_ca_file`.

## Two ways to reach Postgres -- try both yourself

Everything above runs automatically (the CronJobs), but both paths are
just as easy to drive by hand as one specific Teleport user, to see
exactly what each one looks like. Full walkthroughs (getting the SVID,
starting VNet, troubleshooting) are in `clients/cli/README.md` -- this
is the condensed, side-by-side version. **Run path 1's commands from
the same directory** (`./svids` is relative, and the `tsh vnet` command
below needs its own terminal, easy to lose track of) -- a wrong/missing
`sslcert` path fails with a confusing `FATAL: connection requires a
valid client certificate` rather than a clear "file not found" (libpq
silently skips presenting a cert instead of erroring); see
`clients/cli/README.md` step 4 if you hit that.

**The exact resource/role names below (`$CLI_ROLE_NAME`,
`$WORKLOAD_IDENTITY_NAME`, `$APP_NAME`) all include the random suffix
`setup.sh` generated into `.env`** (see the "Unique suffix" section of
`.env.example`) -- they are NOT the literal strings shown in
`teleport/*.yaml`'s comments. Load the real values into your shell
first (from the `postgres/` directory, or adjust the path):

```bash
set -a && source .env && set +a
```

**1. Workload Identity + TCP Application Access** (the point of this
demo) -- you present a SPIFFE X.509-SVID as your own Postgres client
certificate; Teleport only provides the network path, never sees your
data.

**Role required: `$CLI_ROLE_NAME`** (`setup.sh` creates this role, but
assigning it to *your* user is a separate, manual step you have to do
yourself):

```bash
tctl users update <you> --set-roles=<your-existing-roles>,$CLI_ROLE_NAME
```

Then:

```bash
tsh login --proxy=$TELEPORT_PROXY_ADDR
tsh workload-identity issue-x509 --output ./svids --name-selector $WORKLOAD_IDENTITY_NAME --credential-ttl 1h
# start this in another terminal and return
tsh vnet   # leave running in its own terminal -- no `tsh apps login` needed

# tsh apps ls also shows it, if you want to double check
psql "host=$APP_NAME.${TELEPORT_PROXY_ADDR%:*} port=5432 dbname=demo user=app_user sslmode=require \
  sslcert=./svids/svid.pem sslkey=./svids/svid_key.pem"
```

VNet intercepts DNS for Teleport-protected apps and routes matching
connections through Teleport automatically while it's running -- no
local port to track, and the app is reachable at
`$APP_NAME.<proxy-address-without-the-port>` (see `clients/cli/README.md`
step 3). No Postgres server CA to fetch here either: `sslmode=require`
still forces encryption and still presents your SVID as the client
certificate (so `cert` auth on the server side works exactly the same)
-- it just skips verifying Postgres' *own* identity, which isn't the
point being demonstrated here (see `clients/cli/README.md` step 4 if
you want that check too).

```sql
BEGIN;
INSERT INTO transactions (account, amount, description)
  VALUES ('wi-demo-cli', 42.00, 'Deposit via Teleport Workload Identity (CLI)')
  RETURNING id;
SELECT id, account, amount, description, created_at FROM transactions ORDER BY id DESC LIMIT 1;
COMMIT;
```

**2. Plain Teleport Database Access with auto-user-provisioning**
(`ENABLE_DB_SERVICE=true` in `.env`, on by default) -- no certificate
files, no shared `app_user`; Teleport auto-creates a Postgres login
named after *you*.

**Role required: `${CLI_ROLE_NAME}-db-access`** -- a *different* role
from path 1; you need both assigned if you want to try both paths:

```bash
tctl users update <you> --set-roles=<your-existing-roles>,${CLI_ROLE_NAME}-db-access
```

Then:

```bash
tsh login --proxy=$TELEPORT_PROXY_ADDR
tsh db connect --db-name=demo --db-roles=reader,writer $APP_NAME
```

```sql
BEGIN;
INSERT INTO transactions (account, amount, description)
  VALUES ('wi-demo-dbaccess', 42.00, 'Deposit via Teleport Database Access')
  RETURNING id;
SELECT id, account, amount, description, created_at FROM transactions ORDER BY id DESC LIMIT 1;
COMMIT;

-- Confirm it's really you, not "app_user" or anyone else:
SELECT current_user;
```

Both roles already exist once you've run `./setup.sh` (see
`teleport/role-human-cli.yaml` and `teleport/role-db-access.yaml`) --
what's missing by default is *assigning* either one to your own
Teleport user, which only you can do for yourself.

## Directory layout

| Path | What it is |
|---|---|
| [`CERTIFICATES.md`](CERTIFICATES.md) | How the mTLS certificates work: where each CA/cert comes from, how `pg_hba.conf` maps a certificate to a Postgres login. |
| `postgres-chart/` | Helm chart wrapping `bitnami/postgresql`: sample `demo` database, mTLS enforced. |
| `tbot-chart/` | Helm chart: `tbot` issuing SVIDs to a Secret. No tunnel/proxy -- see "How the pieces fit together" above. |
| `teleport/` | Teleport-side resources (`workload_identity`, roles, `bot`) and agent config fragments. |
| `clients/python/` | Python client (`chart/app/transact.py`) + Helm chart (runs as a self-compiling CronJob, one transaction every two minutes, by default; optional Dockerfile for a pre-built image). |
| `clients/go/` | Go client (`chart/app/main.go`) + Helm chart (runs as a self-compiling CronJob, one transaction every two minutes, by default; optional Dockerfile for a pre-built image). |
| `clients/cli/` | Step-by-step walkthrough doing the same thing with `tsh` + `psql`. |
| `setup.sh` / `teardown.sh` | Deploy/tear down everything above from `.env`. |

## Deploying

```bash
cp .env.example .env
$EDITOR .env   # at minimum, set TELEPORT_PROXY_ADDR
tsh login --proxy=<your-proxy-address>
./setup.sh
```

Preview first with `./setup.sh --dry-run` -- it renders every Teleport
resource and the full manifest set for every Helm release (via Helm's
own `--dry-run=client`) without creating or changing anything, so you
can review exactly what would happen before it does. Add `--debug` for
`set -x` plus Helm's own `--debug` output (most useful combined with
`--dry-run`, to see fully rendered manifests including computed
values). `./setup.sh --help` lists both flags.

`setup.sh` (idempotent -- safe to re-run after editing `.env`):

1. Applies the always-on Teleport resources in `teleport/` (`workload_identity`,
   `role-tbot`, `bot`, `role-human-cli`), plus `role-db-access` if
   `ENABLE_DB_SERVICE=true`.
2. Generates a short-lived join token for `tbot` and self-issues the
   Workload Identity trust bundle using *your own* `tsh` session, to
   populate the `teleport-spiffe-ca` Secret Postgres trusts.
3. If `ENABLE_DB_SERVICE=true`, exports Teleport's `db_client` CA into a
   Secret too.
4. `helm upgrade --install`s `postgres-chart` (auto-fetching the
   `bitnami/postgresql` dependency).
5. Deploys a Teleport agent (`teleport-kube-agent`, unless you set
   `DEPLOY_TELEPORT_AGENT=false`) registering Postgres as a TCP
   Application (and a Database Access target, if enabled).
6. `helm upgrade --install`s `tbot-chart`.
7. Deploys the Python and/or Go client CronJobs (`DEPLOY_PYTHON_CLIENT`/
   `DEPLOY_GO_CLIENT`, both default `true`), each running one
   transaction every two minutes -- no registry needed by default, each run
   self-compiles from its own bundled source in a stock `ubuntu` image
   (set `CLIENT_IMAGE_REGISTRY` to build+push a real image instead, for
   faster run startup).
8. Prints a numbered checklist for confirming the deployment is healthy
   -- pod/probe status, tbot's join, Postgres' Service reachability, a
   sample transaction, and (if enabled) `tsh db connect`.

To remove everything (Helm releases, Secrets, the namespace, and the
Teleport resources): `./teardown.sh` (prompts for confirmation; `-y` to
skip, `--keep-namespace` to leave the namespace/PVCs alone).

For the command-line version (no Kubernetes client Job, just `tsh` +
`psql` from your workstation), see `clients/cli/README.md`.

## Confirming the Python and Go clients actually connected and ran a transaction

Each client is a Kubernetes `CronJob` named `pg-client-python-$SUFFIX` /
`pg-client-go-$SUFFIX` (`setup.sh` sets both the Helm release name and
each chart's `fullnameOverride` to that -- they're the same string here,
unlike some other releases in this demo) that runs `schedule: "*/2 * * *
*"` -- every two minutes (cron's minimum granularity is one minute; there's
no sub-minute schedule syntax). Each scheduled run spawns its own one-shot `Job` with
an auto-generated, timestamp-suffixed name, so don't hardcode a Job
name -- select by label instead. (`$NAMESPACE`/`$SUFFIX` below assume
you've run `set -a && source .env && set +a` first, as in "Two ways to
reach Postgres" above.)

```bash
# See the CronJob itself, and every run it's spawned:
kubectl get cronjob -n $NAMESPACE
kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/instance=pg-client-python-$SUFFIX

# What did the latest run(s) actually do?
kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=pg-client-python-$SUFFIX --tail=20
#   Inserted and committed transaction: (<id>, 'wi-demo-python', 42.0, 'Deposit via Teleport Workload Identity (Python)', ...)

kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=pg-client-go-$SUFFIX --tail=20
#   Inserted and committed transaction #<id>: account=wi-demo-go amount=42.00 description="Deposit via Teleport Workload Identity (Go)" created_at=...

# Don't want to wait up to two minutes for the first run?
kubectl create job -n $NAMESPACE --from=cronjob/pg-client-python-$SUFFIX manual-py-$(date +%s)
kubectl create job -n $NAMESPACE --from=cronjob/pg-client-go-$SUFFIX manual-go-$(date +%s)
```

If a run's `COMPLETIONS` shows `0/1` and stays there, check `kubectl
describe job/<name> -n $NAMESPACE` and the pod's logs -- the most common
causes are the SVID Secret not existing yet (tbot hasn't finished its
first join, see step 2 in the "Deploying" checklist above) or the
SVID/CA Secrets not being mounted yet. Both client charts retry the
initial connection within a single run (`CONNECT_RETRIES`, default 10
attempts over ~30s), so a transient failure right after `helm install`
self-heals on the very next scheduled run regardless; a run that's still
failing a few minutes after tbot is confirmed joined has a real
problem, not just a timing race. Each self-compiling run also takes
~15-30s just for `apt-get`/`pip`/`go build` before it even attempts to
connect -- that's expected, not a hang (see `selfCompile` in each
chart's `values.yaml` if you'd rather trade that for a pre-built image).

To confirm it was genuinely authenticated via Workload Identity (not,
say, silently falling back to some other auth path), check the seed data
is still there alongside the new row -- `seed-001`/`seed-002` were
inserted by `postgres-chart`'s initdb scripts, so seeing both the seed
rows and your new `wi-demo-python`/`wi-demo-go` row in the same table
confirms the client reached the real `demo` database, not some other
instance:

```bash
kubectl exec -n $NAMESPACE postgres-0 -- \
  psql -U postgres -d demo -c "SELECT account, amount, description FROM transactions ORDER BY id;"
```

## AI agent integration

`clients/python/chart/app/transact.py` is deliberately split into a reusable
`connect()` (the Workload-Identity-authenticated connection) and a
`run_demo_transaction()` payload marked with an "AGENT INTEGRATION
POINT" comment -- a starting point for wiring a database tool into an
agent framework (LangChain, MCP, etc.) that needs its own Workload
Identity credentials rather than a shared password.

## What's been verified vs. what to double-check

`postgres-chart`, `clients/python`, and `clients/go` were tested
end-to-end against a real `bitnami/postgresql`-backed deployment on a
local Kubernetes cluster, using hand-generated mTLS certificates
standing in for Teleport-issued SVIDs (same `pgHbaConfiguration`/TLS
wiring the chart uses, same client code, same CN-based `cert` auth) --
Postgres came up healthy and both clients completed a real transaction,
connecting straight to the Service and using `sslmode=verify-full` --
at the time, that only worked by coincidence, because the clients went
through tbot's tunnel in every other environment (see the `verify-ca`
bullet below); the architecture was later changed so a direct
connection is what the Python/Go clients actually do everywhere now
(see "How the pieces fit together" above), which is what makes
`verify-full` correct again, for real this time.

`setup.sh --dry-run` was also run against a real, live Teleport cluster
end-to-end, and every resource in `teleport/` plus `setup.sh`'s
`generate_join_token()` were applied for real against that same cluster
(then cleaned up). Both rounds of live testing caught and fixed real
bugs that pure code review missed:

- bitnami's default health probes need the chart's own CA trusted too
  (not just the Teleport bundle), and `bitnami/postgresql`'s Service
  name under `architecture: standalone` is just the fullname
  ("postgres"), not "postgres-primary" as an initial, unverified
  assumption had it.
- Reconstructing an existing CA from a Secret for `genSignedCert` needs
  sprig's `buildCustomCert`, not a plain `dict` -- they look identical
  until you actually try to sign a new cert with the reconstructed CA.
- Status/log output inside functions invoked via `$(...)` command
  substitution must go to stderr, not stdout, or it gets silently
  concatenated into the captured value (this broke `--dry-run`
  specifically, embedding ANSI escape codes into a placeholder token
  that Helm's YAML parser then rejected as invalid control characters).
- The `teleport-kube-agent` chart validates whether app/db access is
  configured from its own top-level `apps:`/`databases:` values, not
  from anything nested inside its `teleportConfig:` passthrough --
  `teleport/{app,db}-service-teleport-config.yaml` are kept as reference
  for the manual-merge path, but `setup.sh` builds the agent's real
  config directly to avoid this.
- `tctl tokens add` has no `--bot` flag and no way to set multiple
  `roles` -- it can't create a token bound to a specific bot name or a
  combined `[App, Db]` agent token. Fixed by having `setup.sh` create a
  `kind: token` resource directly instead (see `teleport/token.yaml`).
- Two `workload_identity.yaml` fields that looked right from docs were
  rejected by the real server: `maximum_ttl: 1h` (protobuf `Duration`
  fields need `"3600s"`, not Go-style `"1h"`) and `rules.allow: -
  conditions: []` ("must be non-empty" -- omitting `spec.rules` entirely
  is what actually means "no extra condition, RBAC only").

**Since then, the entire pipeline has been deployed and confirmed
working end-to-end on a real, live, shared Teleport cluster** (not just
dry-run/render-tested) -- `helm install`ed for real, not just previewed.
That surfaced (and fixed) three more real bugs no amount of dry-running
or code review would catch, since they only manifest once pods actually
run:

- `TELEPORT_AGENT_RELEASE` defaulting to the generic "teleport-agent"
  collided with another team's existing release on the shared cluster --
  the `teleport-kube-agent` chart's `ClusterRole`/`ClusterRoleBinding`
  are cluster-scoped (not per-namespace) and named after the release
  name, so Helm refused to "adopt" one it didn't create. Default changed
  to `postgres-wi-demo-agent`.
- `tbot-chart`'s default image (`public.ecr.aws/gravitational/tbot`)
  doesn't exist for Teleport 18.x -- confirmed via `docker manifest
  inspect` that only `tbot-distroless` is published at that tag. Also
  needed an explicit `POD_NAMESPACE` env var (Kubernetes downward API)
  on the tbot container -- without it, tbot exits immediately with
  "unable to detect namespace", since its `kubernetes_secret` output
  destination needs to know where to create the Secret and there's no
  other way for it to find out.
- tbot's `kubernetes_secret` destination names its output keys
  `svid.pem` / `svid_key.pem` / `svid_bundle.pem` (plus `svid_crl.pem`),
  **not** `svid.pem`/`svid.key`/`bundle.pem` as originally assumed from
  the `directory` destination's naming (which this demo doesn't
  actually use anywhere) -- confirmed by reading the real mounted
  Secret. Fixed in both `transact.py` and `main.go`.
- Kubernetes defaults Secret volume files to mode 0644 (world-readable),
  which libpq's private-key check rejects outright -- both client
  charts' `job.yaml` now set `defaultMode: 0440` on the SVID volume
  (matching what `postgres-chart` already did for its own TLS Secrets).
- `sslmode=verify-full` failed for every client at this point, always:
  they all connected through a Teleport tunnel (tbot's `application-tunnel`
  output for the Python/Go clients, or a human's `tsh vnet` session for
  the CLI), so the hostname they dialed never matched the server cert's
  actual SANs (which name Postgres' own Service). Fixed by switching to
  `sslmode=verify-ca` everywhere (still validates the cert chain, just
  skips hostname pinning) -- in `transact.py`, `main.go`, and
  `clients/cli/README.md`'s `psql` example.

With all of the above fixed, a real transaction was confirmed end-to-end
on the live cluster from both the Python and Go clients: `tbot` joined,
issued an SVID, the tunnel accepted connections, and `psycopg`/`pgx`
both authenticated to Postgres purely via the SPIFFE certificate and
committed a row -- no passwords anywhere.

**Later, the architecture changed again:** tbot's `application-tunnel`
output was removed entirely for the Python/Go clients. The point of
Workload Identity is that a workload doesn't need Teleport to stay in
the network path once it holds a credential -- and since these
CronJobs already run inside the cluster with a real route to Postgres'
Service, routing them through a Teleport tunnel was demonstrating App
Access, not Workload Identity's actual value. They now connect directly
to the `postgres` Service using the SVID as their client certificate
(see "How the pieces fit together" above and
[CERTIFICATES.md](CERTIFICATES.md)), which also means their hostname
now legitimately matches the server cert's SANs -- so they switched
back to `sslmode=verify-full`, correctly this time. The CLI path is
unaffected: a human's workstation still isn't inside the cluster, so it
still needs `tsh vnet` (Teleport TCP Application Access) and still uses
`sslmode=verify-ca`/`require` for the reason described above. This
specific change (tbot-chart's tunnel removal, the client `sslmode`
flip, `role-tbot.yaml` losing its now-unneeded `app_labels` grant) was
made from code review, not re-verified against a live cluster the way
the rest of this section was -- worth confirming for yourself if you
depend on it. See `teleport/README.md` for what else is still worth
double-checking beyond this.

## Why the CronJobs self-compile instead of using a pre-built image

By default, the Python and Go CronJobs don't pull a `postgres-wi-client-python`/`-go`
image at all -- each scheduled run pulls a stock `ubuntu` image, installs
the language toolchain, and builds/runs `clients/{python,go}/chart/app/`
straight from the ConfigMap-mounted source (see `selfCompile` in each
chart's `values.yaml`). That's deliberate: it means this demo needs
nothing pushed to any registry the cluster can pull from -- clone the
repo, run `./setup.sh`, and it works on any cluster with outbound
internet access, no image build/push step and no registry credentials
required. The trade-off is a slower cold start per run (~15-30s for
`apt-get`/`pip`/`go build` before the transaction even begins, see
"Confirming the Python and Go clients" above) instead of an
already-built image starting instantly. Set `CLIENT_IMAGE_REGISTRY` in
`.env` if you'd rather build+push a real image once (via
`clients/*/Dockerfile`) and have `setup.sh` deploy that instead.
