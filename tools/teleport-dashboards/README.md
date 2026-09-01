# Teleport Grafana Dashboards

Five dashboards for self-hosted Teleport, plus the machinery to render them for a specific
deployment and prove the numbers on them are real.

| Dashboard | Audience | Panels | README |
|---|---|---|---|
| **Executive Summary** | VP / Director, quarterly | 17 | [teleport-executive.md](dashboards/teleport-executive.md) |
| **Identity Security** | Analyst — access posture | 25 | [teleport-identity-security.md](dashboards/teleport-identity-security.md) |
| **Ops Health** | SRE — "what pages me at 2am" | 14 | [teleport-ops-health.md](dashboards/teleport-ops-health.md) |
| **Identity & Access** | Security / SE — who accessed what | 9 | [teleport-identity.md](dashboards/teleport-identity.md) |
| **Overview (TV)** | Ops huddle, single screen | 9 | [teleport-overview.md](dashboards/teleport-overview.md) |

The Executive board is the entry point; every tile on it drills into one of the analyst boards.
Each README explains that dashboard panel by panel — what it answers, where the number comes from,
and **why it is built the way it is rather than the obvious simpler way that would be wrong**.

---

## Why these exist in this shape

Two beliefs drove nearly every design decision here, both learned the hard way on a live cluster.

### A wrong number is worse than no number

Validating these dashboards against real data — rather than reviewing the JSON — found defects in
every one of them. Not typos: queries that ran clean, returned plausible values, and measured the
wrong thing.

- A **security board showed a green `0`** for active alerts while 22 high-severity alerts were open.
  The query filtered `status='OPEN'`, a string that never occurs in that schema.
- **"Worker Nodes Ready" read 2 when the answer was 1**, counted the control plane, and *could never
  decrease* — it counted metric series, and kube-state-metrics keeps emitting a `status="true"`
  series at value 0 when a node goes NotReady.
- A **"Failed Logins" tile was structurally incapable** of showing a failed login. The metric it used
  is not exported by the service that evaluates logins. It read 0 while the audit log held 27.
- **Backend latency mixed the Postgres backend with the in-memory cache**, understating real P99 and
  overstating throughput — and defeating the panel's own stated purpose of telling those apart.
- A collector labelled **"faithful"** wrote `0` for a month after its credentials expired, because it
  logged each failed fetch and then saved the snapshot anyway.

None of these look broken. That is the point, and it is why this directory ships a validator rather
than trusting review.

### Absent and zero must be different states

A panel that reads `0` because its datasource is missing is indistinguishable from a real
measurement of zero. So:

- **Panels are omitted, not shown empty.** The renderer drops panels whose capabilities a deployment
  lacks, and records what it dropped in the dashboard description.
- **A failed collector withdraws its metrics** rather than publishing zeros, so Prometheus records
  staleness and the panel reads *No data*.
- **Confidence labels** on the Executive board mark each figure Measured, Approximate, or
  Authoritative, so nobody mistakes an audit-event estimate for a billing figure.

---

## Requirements

| Capability | Provided by | Needed for |
|---|---|---|
| `prometheus` | Teleport diagnostics scraped by Prometheus | Ops Health, most of Overview and Identity |
| `audit.postgres` | Postgres audit backend, `SELECT` on `public.events` | Login and activity panels |
| `accessGraph` | Teleport Enterprise + Identity Security | All of Identity Security, the Executive posture row |
| `cnpg` | CloudNativePG with `enablePodMonitor: true` | The Postgres row on Ops Health |
| `kubeStateMetrics` | kube-state-metrics and cAdvisor | Node and container panels |
| `usageExporter` | The [teleport-usage exporter](exporter/) | MFA policy, TPR, Estate Coverage |

Grafana datasources: `DS_PROMETHEUS`, and `DS_ACCESS_GRAPH` / `DS_TELEPORT_BACKEND` (both Postgres)
where those capabilities are present. Panels reference them through dashboard variables, never by
hardcoded UID, so the same JSON works against any Grafana.

**Nothing here is licence-restricted.** The exporter links only `teleport/api`, which is Apache 2.0.
Enterprise *features* determine which panels have data, not whether anything runs.

---

## Installing

Dashboards are the **source** set. Render them for your deployment first — installing them raw puts
panels on screen whose datasources you do not have.

```bash
# 1. Pick or write a profile describing what your cluster supports.
cat profiles/oss-postgres.yaml

# 2. Render.
make render PROFILE=oss-postgres
#   → scripts/render-dashboards.py --profile profiles/oss-postgres.yaml \
#       --out chart/dashboards

# 3. Install.
helm upgrade --install teleport-dashboards chart \
  --set profile=oss-postgres
```

The chart ConfigMaps the rendered JSON for the Grafana sidecar and **fails the install** if the
directory is empty rather than silently deploying nothing. See
[the chart README](chart/README.md) for values, and for the four non-Helm
delivery paths — Grafana's HTTP API, file provisioning, Terraform and Grizzly all consume the same
rendered files.

### What each profile produces

| Profile | Dashboards | Panels |
|---|---|---|
| `full-enterprise` | 5 | 73 |
| `oss-postgres` | 4 | 39 — Identity Security omitted entirely |
| `cloud` | 1 | 5 — Executive only |

The `cloud` row is worth dwelling on. Teleport Cloud exposes no scrapeable diagnostics endpoint and
no backend database, so **every panel here lost its datasource and that profile rendered nothing at
all**. The usage exporter reads the API instead, which Cloud does expose, so Cloud now gets a real
executive view. That is the clearest argument for the exporter existing.

Profiles are documented in [`profiles/README.md`](profiles/README.md).

---

## Proving the numbers

```bash
make validate                                    # offline: renderer tests, all profiles, chart lint
./scripts/validate-dashboards.py --prom http://localhost:9090   # live: executes every query
```

The validator runs every panel's PromQL and SQL against a live cluster and fails on the specific
ways these dashboards have actually been wrong:

| Check | Catches |
|---|---|
| `L1` | `rate()`/`increase()` over a **gauge** — Teleport ships gauges named `_total`, and this cost us a real bug |
| `L2` | A window longer than Prometheus **actually holds**, using the lesser of configured retention and oldest sample |
| `L3` | `count()` over kube-state condition series — counts series, not resources, and cannot fall |
| `L4` | Metric names that do not exist |
| `S2`/`S3`/`S5` | Overlapping panels, undeclared variables, drill-downs to dashboards that do not exist |
| `D1`–`D3` | Query errors, empty results, and NaN or Inf rendered as plausible values |
| `C1` | **Two independent sources disagreeing.** The others cannot catch a datastore that is confidently wrong. |

`C1` is the one that matters most. When a collector's credentials expired and it recorded zeros for
a month, every single-source check passed: the query succeeded, returned a row, and the value was
neither empty nor NaN. Only asking a second source detects that.
[`scripts/corroborations.json`](scripts/corroborations.json) currently cross-checks TPR three
ways, plus collector health, freshness and version skew.

**The validator self-tests.** `scripts/testdata/dashboard-selftest.json` carries one deliberately
broken panel per check, drawn from bugs actually found here, and must report exactly 7 errors. A
check that silently stops firing is worse than no check — that happened once already, when a
NaN-detection fixture stopped detecting NaN the moment somebody logged in and `0/0` became `1`.

---

## Conventions

**UIDs are a contract.** Drill-downs reference `/d/<uid>/…` directly, and a link to a UID that does
not exist fails only when clicked. `S5` enforces it, and the renderer strips links to dashboards a
profile skipped.

**`x-requires`** on each panel names the capabilities it needs. Grafana ignores unknown panel keys,
so it is inert at runtime; it is what the renderer filters on.

**Retention is two clocks, not one.** `$prom_retention` and `$audit_retention` are separate
variables because on the reference cluster Prometheus held 7 days while the audit database held 116.
One shared value would either truncate the audit panels or ask Prometheus for data it discarded —
and the second failure is silent, because Prometheus answers with whatever it still has.

**`rendered/` and the chart's `dashboards/` are generated.** Edit the source in this directory and
re-render; hand edits to rendered output are discarded.

---

## A note on the git history

The accuracy fixes described in these READMEs were swept into commits whose messages describe
something else — `554a18a` ("declare per-panel capability requirements") and `cd37292` ("normalise
UIDs"), because a path-scoped `git add` was followed by an unscoped `git commit`. The reasoning for
those changes therefore does not appear in the log where you would look for it.

That is much of why these per-dashboard READMEs exist, and why the panel `description` fields carry
their own justification. Read the READMEs, not `git log --follow`, to understand why a panel is
shaped the way it is.
