# Teleport — Ops Health

`teleport-ops-health.json` · uid `teleport-ops-health` · 14 panels in 4 rows ·
default range `now-1h` · refresh `30s` · tags `teleport`, `rev-tech`.

This is the on-call board: "what would page me at 2am?" It is aimed at the SRE
or platform engineer who owns a self-hosted Teleport cluster and needs to
decide, in under a minute, whether the control plane is healthy and — if it is
not — which layer is at fault: the Teleport processes, the Postgres backend,
the audit/session-recording pipeline, or the node the pods are sitting on. It
is deliberately the only one of the five boards that is entirely
Prometheus-sourced, so it keeps working when the audit database or the Access
Graph is unavailable, which is exactly when you need it.

## What it needs

**Datasource.** One Prometheus, selected through the `$datasource` template
variable. No SQL datasource, no Access Graph. Nothing on this board queries
Postgres directly; the Postgres row reads CloudNativePG's `cnpg_*` metrics via
Prometheus.

**Template variables.**

| Variable | Source | Notes |
|---|---|---|
| `$datasource` | datasource picker | type `prometheus` |
| `$namespace` | `label_values(teleport_build_info, namespace)` | the Teleport namespace |
| `$teleport_job` | `label_values(teleport_build_info, job)` | the scrape job for auth/proxy/nodes |

`$teleport_job` only ever resolves to jobs that emit `teleport_build_info` —
i.e. Teleport processes. The CNPG Postgres exporter and the two cluster-health
tiles are therefore anchored on `$namespace` instead (see *Decisions*).

**Capabilities (`x-requires`).** Gating is per panel; the dashboard itself
carries no top-level `x-requires`, because there is no capability whose absence
makes the whole board pointless.

| Capability | Panels | What they are |
|---|---|---|
| `prometheus` | 7 | targets up, target count, backend latency ×2, backend ops/sec, audit emission, audit/S3 errors |
| `cnpg` | 4 | the entire Postgres row |
| `kubeStateMetrics` | 3 | container restarts, memory by pod, CPU by pod |

`scripts/render-dashboards.py` drops any panel whose requirements are not all
present in the profile, then removes rows left with no content and repacks
`gridPos`. Panels are omitted rather than rendered empty, because a panel
reading zero because its datasource is absent is indistinguishable from a real
measurement of zero. The renderer appends a note to the dashboard description
listing what it removed.

Concretely, against the profiles in `profiles/`:

- **`full-enterprise`** — all 14 panels.
- **`oss-postgres`** — no `cnpg`, so the four Postgres panels and the
  "Postgres (CNPG)" row header disappear; 10 panels survive. The Backend
  Performance row still works: `backend_*` comes from Teleport, not from the
  database operator.
- **No scrapeable Prometheus** — with none of `prometheus`, `kubeStateMetrics`
  or `cnpg`, every panel is dropped and the renderer skips the dashboard
  entirely rather than publishing an empty shell. This board is the most
  Prometheus-dependent of the set and degrades least gracefully.

One naming wrinkle worth knowing: the `kubeStateMetrics` capability is used as
shorthand for "kube-state-metrics **and** cAdvisor are scraped". The restart
table genuinely reads `kube_pod_container_status_restarts_total` from
kube-state-metrics, but the memory and CPU panels read `container_*` from
cAdvisor/kubelet. On kube-prometheus-stack they arrive together, which is why
they share one flag.

**Retention is not a constraint on this board.** The longest window anywhere is
`[15m]`; rates use `[5m]`; `$__range` follows the default 1h picker. There is
no `$prom_retention` variable, so the renderer's retention injection is a no-op
here by design. Do not "fix" that.

## Panels

### Row: Cluster Health

**Teleport Targets Up** (`stat`, `prometheus`) — `avg(up{namespace=~"$namespace"})`,
red below 0.9, green at 1.0.

Answers: is everything Prometheus is supposed to be scraping in this namespace
actually answering?

The important detail is the selector: **namespace, not `$teleport_job`.**
`$teleport_job` is derived from `teleport_build_info`, and the CNPG Postgres
exporter (`job="teleport/teleport-postgres"`) does not emit that metric. Scoped
to the job variable, the exporter that feeds the *entire* Postgres row could be
down and this tile would still read a green 100%. Anchoring on namespace pulls
it in.

**Scraped Targets Up (count)** (`stat`, `prometheus`) —
`count(up{namespace=~"$namespace"} == 1)`, green at 7.

This exists because the tile next to it is an average, and an average only
covers targets that still exist. Scale a Deployment to 0 and its series leaves
Prometheus entirely; `avg(up)` over the survivors stays at 1.0 while you have
lost a component. The count goes down. Read the two together.

Expected value on the reference cluster is 7: two proxies, one auth, the SSH
node, grafana-agent, prometheus-agent, and the Postgres exporter. Not scraped
at all today, and so not counted: `teleport-access-graph`, `tbot`,
`approval-bot`, `usage-tracker`. If you add scrape targets, move the threshold.

**Container Restarts** (`table`, `kubeStateMetrics`) — two instant queries:
`sum by (pod) (increase(kube_pod_container_status_restarts_total{...}[$__range])) > 0`
and `max by (pod, container) (kube_pod_container_status_restarts_total{...}) > 0`.

The original was the range query alone, unfiltered. At the default 1h window it
rendered **19 rows of zeros** — one per container — while access-graph sat on 5
lifetime restarts and auth on 4. Every real signal was off-screen below the
fold, behind a wall of healthy pods.

Two changes. First, `> 0` on both series, so only containers with something to
say appear. Second, the lifetime column, which is the one to trust: a restart
that happened before the dashboard window is invisible to `increase()`, and so
is a restart belonging to a pod that has since been replaced — the replacement
is a brand new series starting at 0. The range column tells you "recently"; the
lifetime column tells you "at all".

### Row: Backend Performance

All three panels split by `component`. This is the single most consequential
correction on the board, so the reasoning is stated once here and applies to
all of them.

`backend_read_seconds`, `backend_write_seconds`, `backend_read_requests_total`
and `backend_write_requests_total` are emitted with a `component` label that
takes two values on this cluster: `backend`, meaning the real Postgres backend
(auth only), and `cache`, meaning Teleport's in-memory cache. They are two
different storage systems with latency profiles three orders of magnitude
apart. The panels summed them.

The result was not a rounding error, it was the wrong number. Measured on the
live cluster: real backend read P99 was **3.62 ms** while the mixed panel
displayed **2.92 ms**, and backend reads/sec were overstated at **3.13** against
an actual **2.04**. Worse, the mixing defeated the panel's own stated purpose.
The question an SRE brings to this row is "is this cache pressure or is Postgres
slow?", and a single blended line cannot answer it — a cache thrash and a
Postgres stall move the same line in the same direction. Split, they are
immediately distinguishable.

**Backend Write Latency (P50/P95/P99)** (`timeseries`, `prometheus`) —
`histogram_quantile(q, sum(rate(backend_write_seconds_bucket{...}[5m])) by (le, component))`
for q ∈ {0.50, 0.95, 0.99}.

P50 is kept here. Backend writes are genuinely spread across buckets, so the
median lands on a real observation. Sustained P99 above 100 ms on the `backend`
series is worth investigating. The `cache` series is a different story: ~100% of
cache writes land in the first bucket (`le=0.001`), so all three cache
percentiles are linear interpolation inside [0, 1 ms]. Read them as "below
resolution", not as measurements.

**Backend Read Latency (P95/P99)** (`timeseries`, `prometheus`) — same shape,
`backend_read_seconds_bucket`, **P50 deliberately removed**.

93.6% of `backend` reads and 100% of `cache` reads fall in the first histogram
bucket (`le=0.001`). When more than half the observations are in the first
bucket, `histogram_quantile(0.50, …)` has no observation to anchor on and
returns a point interpolated linearly inside [0, 1 ms]. It looks like a
measurement, moves like a measurement, and is an artifact of the bucket
boundary. It was dropped rather than left to be read as fact. For the same
reason, treat the `cache` P95/P99 as "sub-millisecond" rather than as exact
values.

Note this is why the two latency panels have different titles and different
series counts. That asymmetry is intentional; it is not drift.

**Backend Ops/sec (Writes vs Reads, by component)** (`timeseries`, `prometheus`)
— `sum by (component) (rate(backend_{write,read}_requests_total{...}[5m]))`.

The `backend` series is the load actually reaching Postgres; `cache` never
touches the database. Correlate this with the Postgres row: a sudden spike in
backend writes is usually a heartbeat storm (resources re-registering en masse
after a proxy or auth restart).

### Row: Postgres (CNPG)

**Postgres Replication Lag** (`gauge`, `cnpg`) —
`max(cnpg_pg_replication_lag{...}) and on() (cnpg_pg_replication_streaming_replicas{...} > 0)`,
`noValue: "No standby configured"`, thresholds at 5 s / 10 s.

This cluster runs CNPG with `spec.instances: 1`. There is no standby, so
`cnpg_pg_replication_streaming_replicas = 0` and `cnpg_pg_replication_lag`
reports a flat, permanent `0`. Ungated, the gauge sat green forever and its
thresholds could never fire under any circumstance. That is worse than useless:
it presented "single Postgres pod, no replica, no automatic failover" as a
healthy, monitored HA pair. An on-call engineer glancing at this row would have
concluded the database was covered.

The `and on()` guard makes the series drop out entirely when there is no
streaming standby, which lets Grafana's `noValue` render the honest answer:
*No standby configured*. Add a replica and the gauge starts working with no
edit required.

**Postgres WAL Archiving (single instance, no failover)** (`stat`, `cnpg`) —
`cnpg_pg_stat_archiver_seconds_since_last_archival`,
`cnpg_pg_stat_archiver_failed_count`, `cnpg_pg_stat_archiver_archived_count`.

Added alongside the gated gauge, because gating a panel to show nothing leaves a
hole where a durability signal should be. With no standby, point-in-time
recovery from archived WAL **is** the recovery story for this cluster — if
archiving stalls, every unarchived write is lost when the node dies. So this
panel measures the guarantee that actually exists rather than the one that does
not.

Reference values from the live cluster: 40,947 segments archived, 19 failures.
"Archive Failures" is a lifetime counter, so a non-zero value is normal after a
restart; a *rising* value is not. "Since Last Archive" climbing without bound
means archiving has stopped.

**Postgres Connections by Database** (`timeseries`, `cnpg`) —
`sum by (datname, state) (cnpg_backends_total{..., usename!="cnpg_metrics_exporter"})`
plus `max(cnpg_pg_settings_setting{name="max_connections"})`.

The previous version grouped only by `state` and did not exclude the exporter.
Its one and only "active" connection was `cnpg_metrics_exporter` querying
`pg_stat_activity` — the scrape observing itself. That series is pinned at 1
forever by construction: every scrape sees exactly one active backend, its own.
The panel was a very stable measurement of nothing.

Excluding the exporter's `usename` and grouping by `datname` shows the real
pools. Expect the Teleport, `access_graph`, and `usage` pools to appear
overwhelmingly as `idle` — pooled connections are idle between statements and
that is the correct steady state, not a symptom. `max_connections` is plotted as
the saturation reference so "is this a lot?" has an answer on the same axes.

**Postgres Database Size** (`timeseries`, `cnpg`) —
`max by (datname) (cnpg_pg_database_size_bytes{namespace=~"$namespace", datname!~"template.*|postgres"})`.

Previously two hardcoded `datname` targets, which silently omitted the `usage`
database (8.1 MB at the time it was found). Databases are now discovered
dynamically; the regex drops the `template*` and `postgres` system databases,
and the `$namespace` selector keeps a second CNPG cluster elsewhere in the
Prometheus from being blended in.

### Row: Audit Pipeline

**Audit Emission Rate** (`timeseries`, `prometheus`) —
`sum(rate(teleport_audit_emit_events{...}[5m]))` with
`sum(rate(audit_failed_emit_events{...}[5m]))` overlaid in red.

The overlay is the point. Emission rate alone tells you the cluster is busy; the
failure line tells you whether the audit record is complete. Any sustained
non-zero red is a problem — a gap in the audit log is a compliance event, not a
performance one.

**Audit/S3 Errors (15m)** (`stat`, `prometheus`) — three targets, red at ≥ 1.

The window is 15 minutes. The panel used to be titled and described as covering
the last hour while its queries used `[15m]`; the description now matches the
PromQL.

1. `sum(increase(audit_failed_emit_events{...}[15m]))` — a true counter,
   `increase()` is correct.
2. `max_over_time(sum(teleport_incomplete_session_uploads_total{...})[15m:1m])` —
   **this metric is a GAUGE despite the `_total` suffix.** Confirmed against
   Prometheus metadata; its help text is "Number of sessions not yet uploaded to
   auth". It legitimately *falls* every time an upload completes. Wrapping it in
   `increase()`, as the panel originally did, ran counter-reset logic over a
   value designed to go down: every completed upload looked like a counter
   reset, and the tile reported an arbitrary number with no physical meaning.
   Reading the gauge's peak over the window is the correct question — "how far
   behind did the upload queue get?"

   This is a recurring trap in Teleport's metric naming, not a one-off.
   `proxy_ssh_sessions_total` is also a gauge. Check the metadata before
   applying `rate()` or `increase()` to any Teleport `_total`.
3. `sum(increase(s3_requests{..., result!="success"}[15m]))` — **new.** The
   panel's title and description promised S3 pipeline health and it queried no
   S3 metric whatsoever. `s3_requests{result!="success"}` showed 3 real failures
   on the live cluster. They had been invisible on a board whose entire job is
   to surface exactly that.

### Row: Resource Pressure

**Memory by Pod** (`timeseries`, `kubeStateMetrics`) —
`sum by (pod) (container_memory_working_set_bytes{namespace=~"$namespace", container=~"teleport|postgres|teleport-access-graph"})`.

**CPU by Pod (cores)** (`timeseries`, `kubeStateMetrics`) — same filter over
`rate(container_cpu_usage_seconds_total{...}[5m])`.

Both previously filtered on a bare `container="teleport"`, which matched 6 of
the 12 containers in the namespace and — critically — excluded
`teleport-postgres-1`, whose container is named `postgres`. The Backend
Performance row spends three panels trying to explain Postgres latency and the
resource row was hiding the Postgres pod. Postgres is currently the single
largest CPU consumer in the namespace. `teleport-access-graph` was added for the
same reason.

## Decisions

**Namespace-scoped, not job-scoped, for anything cross-component.** `$namespace`
is the blast radius; `$teleport_job` is the Teleport processes inside it. Health
tiles that are supposed to answer "is anything broken" must use the former, or
they structurally cannot see non-Teleport components — which on this cluster
means the Postgres exporter and therefore the whole Postgres row.

**Split by `component`, do not sum.** Any `backend_*` metric aggregated without
`by (component)` blends Postgres with an in-memory cache. The mixed numbers were
measurably wrong (P99 2.92 ms shown vs 3.62 ms real; 3.13 reads/s shown vs 2.04
real) and, more importantly, unactionable.

**Delete percentiles that are pure interpolation.** With 93.6% of backend reads
and 100% of cache reads in the `le=0.001` bucket, a read P50 is a bucket-boundary
artifact dressed as a measurement. It was removed from the read panel rather
than annotated, because a plotted line gets believed regardless of the caption.
Write P50 stayed because write latency is genuinely spread across buckets.

**Verify whether a Teleport `_total` is a counter before wrapping it.** Two
confirmed gauges carry the suffix (`teleport_incomplete_session_uploads_total`,
`proxy_ssh_sessions_total`). `rate()`/`increase()` over a gauge that can fall
produces plausible-looking garbage rather than an error, which is why this one
survived so long.

**Gate panels that cannot fire rather than letting them show a reassuring
zero.** The replication-lag gauge is the template: an always-green tile with
unreachable thresholds actively misinforms. Where gating removes a signal,
replace it with the signal that does exist — hence the WAL-archiving panel.

**Exclude the observer from the observation.** The metrics exporter's own
session is a scrape artifact, not workload. Leaving it in pinned the connections
panel at a constant 1.

**Filter tables to non-zero rows.** A 19-row table of zeros is not "complete",
it is a place for real events to hide.

**Show both windowed and lifetime restart counts.** Neither alone is sufficient:
`increase()` over the dashboard range misses older restarts and pod
replacements; the lifetime counter has no sense of "recent".

**Both latency panels split by `component` even though only one has three
percentiles.** The asymmetry between the read and write panels is deliberate and
documented in each panel's own `description` field. Those descriptions are the
authoritative per-panel record; this file explains the reasoning across panels.

## Known limitations

- **`avg(up)` cannot see a target that no longer exists.** Scale a component to
  zero and the percentage tile stays at 100%. The count tile next to it is the
  compensating control, and its green threshold (7) is hardcoded to this
  cluster's target inventory — it will be wrong on yours until you change it.
- **Four components are not scraped at all** and are therefore entirely absent
  from this board: `teleport-access-graph`, `tbot`, `approval-bot`,
  `usage-tracker`. Access-graph appears in the restart, memory, and CPU panels
  (those come from the kubelet, not from the app) but exports no application
  metrics here.
- **Sub-millisecond latency has no resolution.** The first histogram bucket is
  `le=0.001` and most reads land in it. This board cannot distinguish a 0.1 ms
  read from a 0.9 ms read, and will not notice a regression that stays inside
  that bucket. It is built to catch a Postgres stall, not a microbenchmark.
- **No replication signal, because there is no replica.** The gauge says "No
  standby configured" and means it. This cluster has no automatic failover; WAL
  archiving is the whole recovery plan, and this board can only tell you that
  archiving is *running*, not that a restore would succeed. Nothing here tests a
  restore.
- **`s3_requests{result!="success"}` counts failed requests, not lost
  recordings.** A retried-and-succeeded upload increments it. Non-zero means
  look; it does not by itself mean data loss.
- **Incomplete uploads are reported as a peak, not a trend.** `max_over_time`
  over 15 minutes tells you how far behind the queue got, not whether it is
  currently draining or growing. For that, widen the time picker and watch the
  shape.
- **`kube_pod_container_status_restarts_total` resets when a pod is replaced.**
  A pod that crashlooped and was then rescheduled onto another node starts a
  fresh series at 0. The "lifetime" column is the lifetime of the *current*
  pod, not of the workload.
- **No alerting.** Thresholds here colour tiles; they do not page. This board
  assumes somebody is looking at it, which is the wrong assumption at 2am.
  Prometheus alert rules are out of scope for this file.
- **Retention is not a limitation of this board** — the longest query window is
  15 minutes and the default range is 1 hour, comfortably inside any Prometheus
  retention. If you are auditing the dashboards for retention problems, this one
  is not among them; leave it alone.
