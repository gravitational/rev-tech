# Capability profiles

A profile describes what a target cluster can actually support. `scripts/render-dashboards.py`
reads one, drops every panel whose requirements it does not meet, repacks the layout, and writes
a deployable dashboard set.

```bash
./scripts/render-dashboards.py --profile profiles/oss-postgres.yaml --out rendered/oss-postgres
```

**Panels are omitted, not left empty.** A stat tile drawing a large `0` because its datasource is
absent is indistinguishable from a real measurement of zero, and on a board someone makes
decisions from that is worse than the panel not being there. Each rendered dashboard records what
was dropped, and why, in its description.

## The five capabilities

| Capability | How to check it on a target cluster |
|---|---|
| `prometheus` | Is the Teleport diagnostics endpoint scraped? `count(teleport_build_info) > 0`. **False on Teleport Cloud** — the endpoint is not exposed. |
| `audit.postgres` | Is the audit backend Postgres, with `public.events` readable by the Grafana user? `SELECT 1 FROM public.events LIMIT 1`. False for DynamoDB, Athena, S3 and Cloud. |
| `accessGraph` | Is Identity Security licensed and running, with a `tenant_*` schema in the `access_graph` database? Enterprise only. |
| `cnpg` | Is Postgres managed by CloudNativePG with `spec.monitoring.enablePodMonitor: true`? `count(cnpg_pg_database_size_bytes) > 0`. |
| `kubeStateMetrics` | Are kube-state-metrics and cAdvisor scraped? `count(kube_node_status_condition) > 0`. False outside Kubernetes. |

## Variables

`variables:` sets the default of a Grafana dashboard variable at render time. Two matter:

- **`prom_retention`** — Prometheus retention on the target. Every PromQL range selector derives
  from it, so a panel can never claim a window the datastore does not hold.
- **`audit_retention`** — how far back the Teleport audit backend holds events.

**These are deliberately separate and must not be merged.** On the reference cluster Prometheus
held **7 days** while the audit database held **116**. One shared value would either truncate the
audit panels to a week or ask Prometheus for data it discarded — and the second failure is silent,
because Prometheus returns a result computed over whatever it still has.

## The shipped profiles

| Profile | Renders | Notes |
|---|---|---|
| `full-enterprise` | 5 of 5 dashboards, all panels | The reference cluster |
| `oss-postgres` | 4 dashboards | Identity Security skipped entirely (no Access Graph); executive board keeps 6 of 12 panels |
| `cloud` | **nothing** | See below |

### Why `cloud` renders nothing

That is the honest answer, not a bug. Teleport Cloud exposes no scrapeable diagnostics endpoint
and no backend database, so every panel in the current set loses its datasource. The profile exists
so that fact is visible and testable now rather than discovered by a customer on install day.

Making Cloud viable requires the `teleport-usage` exporter, which reaches the Teleport API rather
than a datastore and therefore works on any edition or backend. That is Phase 3.

## Adding a profile

1. Copy the closest existing file and adjust `capabilities`.
2. Render it and check the panel counts are what you expect.
3. Validate the output: `./scripts/validate-dashboards.py --offline --quiet rendered/<name>/*.json`.
4. CI renders and validates every file in this directory, so a broken profile fails the build.

## Two constraints worth knowing

**The profile parser is deliberately minimal.** It is stdlib-only so the renderer runs anywhere,
and it understands exactly `name:`, a `capabilities:` list of `- items`, and a flat `variables:`
map. Nested maps or inline lists will parse wrongly and silently. It fails toward dropping panels
rather than keeping unsupported ones, which is the safer direction, but do not extend the schema
without extending the parser.

**`rendered/` is generated output and is gitignored.** Editing a rendered dashboard by hand is
lost on the next render. Change the source in `dashboards/` and re-render.
