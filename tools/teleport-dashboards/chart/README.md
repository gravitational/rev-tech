# teleport-dashboards

Deploys the Teleport Grafana dashboards as ConfigMaps for the Grafana sidecar to pick up.

## Two steps, and the second one is not optional

```bash
# 1. Render for the target cluster's capabilities
./scripts/render-dashboards.py --profile profiles/oss-postgres.yaml \
  --out chart/dashboards

# 2. Install
helm upgrade --install teleport-dashboards chart \
  --set profile=oss-postgres
```

Or via the Makefile:

```bash
make render PROFILE=oss-postgres
helm upgrade --install teleport-dashboards chart --set profile=oss-postgres
```

The chart **deploys whatever is in `dashboards/`** and does not inspect it. Installing a profile
that does not match the cluster leaves panels whose datasource is absent rendering "No data" —
which is the exact failure the profile mechanism exists to prevent. If the directory is empty the
chart **fails the install** rather than silently deploying nothing.

## Why the chart does not filter panels itself

Helm can read a dashboard with `fromJson` and rebuild it, but removing a panel means recomputing
every subsequent `gridPos`, reflowing rows, and dropping rows left empty. That is impractical in Go
templates and produces diffs nobody can review. `scripts/render-dashboards.py` is a real program
with unit tests; the chart consumes its output.

This split has a second benefit: the rendered JSON is plain Grafana JSON with no templating of any
kind, so Helm is only one of several delivery options.

| Delivery path | How |
|---|---|
| **Helm + sidecar** (this chart) | ConfigMap labelled `grafana_dashboard=1` |
| Grafana HTTP API | `POST /api/dashboards/db` with a service-account token |
| File provisioning | drop the JSON into `/etc/grafana/provisioning/dashboards` |
| Terraform | `grafana_dashboard` resource, `config_json = file(...)` |
| Grizzly | `grr apply -f rendered/<profile>/` |

All four consume the same rendered files. Nothing here is Kubernetes-specific except this chart.

## Connecting to your cluster's data

The dashboards resolve datasources through variables — `DS_PROMETHEUS`,
`DS_TELEPORT_BACKEND`, `DS_ACCESS_GRAPH` — that match **by name** against whatever Grafana has.
Without matching datasources every panel fails, so you have two options.

### Option 1 — you already provision datasources (default)

Leave `datasources.create: false` and make sure these names exist:

| Name | Type | Needed for |
|---|---|---|
| `Prometheus` | prometheus | Ops Health, most of Overview and Identity |
| `Teleport Backend` | postgres, `SELECT` on `public.events` | Login and activity panels |
| `Access Graph` | postgres, `tenant_*` schema | Identity Security (Enterprise) |

Names matter. The variables pin by name regex on purpose: a cluster with several Postgres
datasources otherwise has Grafana bind to whichever sorts first, silently querying the wrong
database and returning plausible rows. `scripts/validate-dashboards.py` enforces this
(`S6-unpinned-datasource`).

### Option 2 — let the chart provision them

```bash
helm upgrade --install teleport-dashboards chart \
  --set profile=oss-postgres \
  --set datasources.create=true \
  --set datasources.prometheus.url=http://prometheus-operated.monitoring.svc:9090 \
  --set datasources.auditBackend.enabled=true \
  --set datasources.auditBackend.host=my-postgres.example.com:5432 \
  --set datasources.auditBackend.existingSecret=teleport-audit-grafana
```

Nothing here assumes CloudNativePG, a namespace, or in-cluster Postgres. `host` can be RDS, a
managed instance, or a service in another namespace.

**Passwords never go in a ConfigMap.** The chart writes datasource provisioning to a **Secret**,
which the Grafana sidecar picks up because kube-prometheus-stack runs it with `RESOURCE=both`.
Supply the password either inline (`--set …password=`) or by referencing an existing Secret
(`existingSecret` / `existingSecretKey`), which is read at install time with Helm's `lookup`.

> `lookup` returns nothing during `helm template` and `--dry-run`, because there is no cluster to
> read. A missing password is therefore a **hard failure** rather than a password-less datasource —
> an install that appears to succeed and leaves every audit panel broken is exactly the failure this
> repo exists to prevent. Render with `datasources.create=false` if you only want the YAML.

Grant the audit user `SELECT` on `public.events` and nothing more. Do not point it at a superuser.

## Values

| Value | Default | Purpose |
|---|---|---|
| `dashboardsDir` | `dashboards` | Directory inside the chart holding rendered JSON. Helm's `.Files.Glob` cannot escape the chart directory, so rendered output must live here. |
| `namespace` | `monitoring` | Namespace the Grafana sidecar watches. |
| `sidecarLabel` | `grafana_dashboard` | Label the sidecar selects on. |
| `sidecarLabelValue` | `"1"` | Value of that label. |
| `folder` | `Teleport` | Grafana folder annotation. Empty means the General folder. |
| `profile` | `""` | Recorded as `teleport.dev/rendered-profile` so a cluster can be audited for which profile it was built from. Informational. |

The two sidecar values are the kube-prometheus-stack defaults. A Grafana deployed differently will
need them changed — check `grafana.sidecar.dashboards.label` and `labelValue` in your Grafana chart
values.

## Dashboard UIDs are a contract

Drill-down links reference other dashboards as `/d/<uid>/…`. A link to a UID that does not exist
fails only when somebody clicks it, so it survives review indefinitely.

| Dashboard | UID |
|---|---|
| Executive Summary | `teleport-executive` |
| Overview (TV) | `teleport-overview` |
| Ops Health | `teleport-ops-health` |
| Identity & Access | `teleport-identity` |
| Identity Security | `teleport-identity-security` |

`scripts/validate-dashboards.py` enforces this with the `S5-dangling-link` check, and the renderer
strips links to dashboards a profile skipped.

**Changing a UID orphans the old dashboard.** Grafana treats it as a new one, the sidecar does not
prune the old record, and the HTTP API refuses to delete a provisioned dashboard. Removing the
ConfigMap and restarting Grafana forces the provisioner to reconcile and drop the orphan.

## Verifying an install

```bash
kubectl -n monitoring get cm -l app.kubernetes.io/name=teleport-dashboards
kubectl -n monitoring logs -l app.kubernetes.io/name=grafana -c grafana | grep "failed to save dashboard"
```

The second command should print nothing. A `found: 2. desired: 1` error there means two ConfigMap
**keys** resolved to the same filename — the sidecar writes by key, not by ConfigMap name, so two
different ConfigMaps using the same key silently overwrite each other. That bug hid a completely
broken `teleport-overview` for months.
