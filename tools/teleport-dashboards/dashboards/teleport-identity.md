# Teleport — Identity & Access

`teleport-identity.json` (UID `teleport-identity`) answers one question for a
security analyst or an SE giving a demo: **who is authenticating, what
certificates are being issued, and is anything anomalous?** Nine panels in five
rows — Authentication, Certificate Issuance, Sessions & Connections, API (gRPC),
Connected Resources — on a 24h default window with a 1m refresh. It is one of
the two analyst boards that `teleport-executive` drills into; `teleport-overview`
is the TV board and `teleport-ops-health` is the SRE page. This one is meant to
be read, not glanced at: most panels have a caveat, and the caveat is in the
panel description.

## What it needs

Two datasources:

| Variable | Type | Bound to | Used by |
|---|---|---|---|
| `$datasource` | prometheus | any Prometheus scraping Teleport | 7 panels |
| `$DS_TELEPORT_BACKEND` | postgres | datasource whose name matches `/[Tt]eleport ?[Bb]ackend/` | 2 panels |

The Postgres datasource must point at the Teleport backend database (`teleport`)
with `SELECT` on `public.events` — the audit table, columns `event_type`,
`event_time`, `event_data` (jsonb). Both login panels read
`event_type='user.login'` and bucket on `event_time`.

**Note:** on this branch `helm/monitoring-values.yaml` provisions only the
`Access Graph` datasource. The `Teleport Backend` datasource exists in the live
Grafana but is not in the repo's Helm values, so a fresh install of the
monitoring stack will not have it and the two login panels will fail to bind.
Provision it (db `teleport`, read-only role, `sslmode: require`) before shipping
this board anywhere new.

Two Prometheus template variables, `$namespace` and `$teleport_job`, are both
derived from `label_values(teleport_build_info, …)`, the same pattern the
upstream Teleport dashboard uses. Every PromQL query is scoped by both.

Capability annotations (`x-requires`, consumed by `scripts/render-dashboards.py`):
`prometheus` × 7, `audit.postgres` × 2. Measured renderer output:

| Profile | Result |
|---|---|
| `full-enterprise` / `oss-postgres` | 9/9 panels |
| prometheus only, no `audit.postgres` | 7/9 — both login panels omitted |
| neither Prometheus nor audit | dashboard SKIPPED entirely (0 of 9 supported) |

Panels are *omitted*, not left to render "No data". On a deployment without a
Postgres audit backend you lose the login view outright. That is the intended
outcome: there is no Prometheus fallback for it that is worth showing, for the
reason in the first panel below.

## Panels

### Authentication

**Logins per Hour, Success vs Failure (audit log)** — bar chart, hourly buckets,
green Success / red Failed, from `public.events`. Sourced from the audit log
rather than Prometheus, and this is the single most important thing to
understand about this dashboard.

`failed_login_attempts_total` is exported **only** by `job="teleport"` (the
proxies) and `job="teleport/ssh-node"`. It is **never exported by
`teleport-auth`** — which is the process that actually evaluates SSO and local
logins. Measured on this cluster: the metric read `0` across every series at 89
days of uptime, while the audit database held **27 real failed logins** (16
`oidc`, 11 `local`). The panel was not merely undercounting; it was structurally
incapable of ever showing the thing it was named after, on any cluster, at any
scale.

The obvious replacement, `user_login_total`, is also not a login counter. It
counts re-authentications and session refreshes: **266 increments since
2026-06-03 against 52 real audit `user.login` successes** over the same window,
roughly 5x over-reporting, with 7 increments landing inside a single 45-minute
re-auth burst that corresponded to one real login.

So the panel counts audit events. That costs portability — the board now needs a
Postgres datasource it previously did not — and the cost is paid deliberately,
because the alternative is a panel that is confidently wrong.

**Login Success Ratio (selected window)** — stat, `count(success=true)/count(*)`
over the same events, `NULLIF(count(*),0)` so an empty window yields NULL rather
than a divide-by-zero.

The previous version divided `increase(user_login_total[24h])` by
`increase(user_login_total[24h]) + increase(failed_login_attempts_total[24h])`.
On an idle cluster both terms are 0, the result is NaN, and in Grafana NaN falls
through to the **base** threshold step — which was red. The panel therefore
rendered a permanent red alarm on a healthy cluster, which is worse than useless:
it teaches the viewer to ignore the panel, and then the panel cannot warn them
about anything.

The fix is two-part. The base step is now **blue** (neutral) with red only from
`value >= 0`, so "no data" and "0% success" are visually distinct; and
`noValue: "No logins in window"` says so in words. Thresholds above that are
orange at 0.9 and green at 0.95. Measured after the change: 24h → *No logins in
window*; 90d → 0.852; all-time → 0.811.

### Certificate Issuance

**User Certificate Issuance Rate (bot-dominated)** — `rate(teleport_user_certificates_generated[5m])`.

The legend used to say "User certs", which read as human logins. It is not. On
this cluster the traffic is ~100% MachineID bot renewal: the audit log shows
**288 `cert.create` and 144 `bot.join` events per day** (exactly two certs per
bot join) against **2 human `user.login` events in 30 days**, and the Prometheus
counter's 24h increase of 286 matches the `cert.create` rate. The legend now says
so. Read it as bot renewal volume; use the audit panels above for human activity.

The `auth_generate_requests_total` series that used to sit alongside it was
removed. It read **10 for all time and 0 over 7 days** — a dead series drawn as a
flat zero *underneath* a series it claims to be a superset of, which invites the
reader to conclude cert issuance is idle.

**Cert Issuance Latency (P95/P99, >20 samples/h)** —
`histogram_quantile(…) and on() (sum(increase(auth_generate_seconds_count[1h])) > 20)`.

The `and on()` gate is the point of the panel. `auth_generate_seconds_count` is
**10 for the entire lifetime of this cluster and 0 over 24h**. A quantile over
that is meaningless: with no samples it is NaN, and with one slow sample it snaps
to a bucket edge and draws a latency spike that never happened. Below 20
observations in the trailing hour the panel says `insufficient samples`, which is
the honest answer. Thresholds (orange 0.5s, red 1s) only apply once the gate
opens; sustained >1s usually means a slow backend.

### Sessions & Connections

**Active SSH Sessions by Role (gauge, counted once per role)** —
`sum by (job) (proxy_ssh_sessions_total{…})`, used bare.

`proxy_ssh_sessions_total` is a **GAUGE** despite the `_total` suffix —
metadata-confirmed, help text "Number of active sessions through this proxy".
Do not wrap it in `rate()` or `increase()`; a future editor "fixing" this query
because of the suffix would be producing nonsense. (`scripts/validate-dashboards.py`
check `L1-gauge-rate` reads live Prometheus metadata and will fail the build if
someone does.)

It is also exported by all 6 Teleport processes, so one live session traversing
proxy → node is reported by both and a bare `sum()` doubles it. Splitting
`by (job)` does not remove the double count — nothing can, from this metric — but
it makes it visible instead of silently baking a 2x into a single number.

**Agent Reverse-Tunnel Connections (not user sessions)** —
`sum by (job, ingress_service) (teleport_authenticated_active_connections{…})`.

This panel was titled "Authenticated Active Connections by Type", which was a
misnomer twice over. There is no "type" to break out: `ingress_service` takes
exactly one value on this cluster, `tunnel`, and only on `job="teleport"`. And
they are not user connections — they are agents (node, kube, app, db, and the
MachineID bots) dialling back to the proxy. A drop here means an agent
disconnected; a rise does not mean users showed up.

It was retitled rather than re-pointed: the metric is genuinely useful for agent
liveness, it was just labelled as something it is not. The `by (job, ingress_service)`
grouping stays so a second `ingress_service` value would appear on its own if one
ever showed up.

### API (gRPC)

**Top 10 gRPC Methods (RPC/sec)** — `topk(10, sum by (grpc_method) (rate(grpc_server_handled_total[5m])))`.
Straightforward; useful for spotting a noisy client or a runaway poll loop.

**gRPC Error Rate (NotFound broken out)** — three series over
`grpc_server_handled_total`, all divided by total RPC rate:

1. `Error rate (excl. NotFound)` — `grpc_code!~"OK|NotFound|Canceled"`. Drives
   the panel colour against 1% / 5% thresholds.
2. `NotFound rate` — `grpc_code="NotFound"`, drawn blue, no fill, no threshold.
3. `All non-OK rate` — `grpc_code!~"OK|Canceled"`, dashed, neutral. The true total.

The previous version filtered `NotFound` out entirely and read a flat green 0%.
`NotFound` is **1,965 of 10,529 RPCs per day (18.6%)** here — routine
`GetWebSession` / `GetClusterMaintenanceConfig` polling. Excluding it keeps the
threshold usable (including it would pin the panel permanently red on an idle
cluster), but excluding it *silently* meant a `NotFound` storm — the classic
symptom of a broken cache or a resource being polled after deletion — could never
surface on this board. Hence: exclude it from the alarm, but draw it.

`Canceled` is excluded from all three series. Long-lived `WatchEvents` streams
terminate that way by design; counting them as errors is just noise.

### Connected Resources

**Connected Resources by Type** — `sum by (type) (teleport_connected_resources{…})`.

This one is correct as-is and was verified rather than changed: app=2, kube=1,
node=1, matching `tctl inventory status` and `tctl apps ls`. An earlier report of
a 2-vs-5 undercount did **not** reproduce.

Two caveats. `teleport_connected_resources` is a **per-auth-instance** gauge —
each auth server reports only the agents keepaliving to *it*. With a single auth
(this cluster) the summed view is exact; under auth HA it over-counts agents that
keepalive to more than one instance, so scope to a single auth instance before
reading absolute numbers.

And the panel deliberately carries **no `timeFrom`**. A 30d `timeFrom` exists on
this panel on another branch and must not be adopted here: Prometheus retention
was raised to 30d in config but the TSDB currently holds ~7d of actual samples
(`profiles/full-enterprise.yaml` pins `prom_retention: 7d` to what is *usable*,
not what is configured), so a 30d window would render roughly 80% empty canvas
and read as an outage. `scripts/validate-dashboards.py` check `L2-window>retention`
fails on exactly this.

## Decisions

- **Correctness beat portability on the login panels.** Moving them to SQL added
  a datasource requirement and cost this board its ability to render on Teleport
  Cloud at all. A Prometheus-only board that reports zero failed logins forever
  is not a more portable board; it is a broken one that travels well.
- **Neutral base threshold steps everywhere a ratio can be empty.** Grafana
  resolves NaN and no-data to the base step. If the base step is red you have
  built a false alarm that fires hardest when nothing is happening. Base steps
  are blue/neutral and paired with an explicit `noValue` string.
- **Gate quantiles on sample volume, don't hide the panel.** `>20 samples/h` with
  `insufficient samples` as the fallback keeps the panel present and honest. An
  absent panel is a question the viewer never asks.
- **Break out rather than filter out.** The `NotFound` fix could have been "keep
  excluding it" (green lie) or "stop excluding it" (permanent red). Three series
  with one driving the threshold is more panel than either, and it is the only
  version where a `NotFound` storm is visible.
- **Rename rather than re-point.** The reverse-tunnel panel's metric was fine;
  only its title was wrong. Swapping in a different metric to match a title
  nobody validated would have been the worse fix.
- **Make double-counting visible rather than hiding it.** `by (job)` on the SSH
  session gauge shows the reader that the same session appears twice, which is
  more useful than a single confidently-doubled number.
- **Delete dead series.** A metric that has recorded 10 events in 89 days does
  not belong on a rate panel; drawn as a flat zero it actively misleads.
- **Panel descriptions carry the reasoning.** Every non-obvious panel states its
  source, its confidence and its caveat in-product, so an analyst reading the
  board at 2am does not have to find this file.

## Known limitations

- **SSH sessions only.** `proxy_ssh_sessions_total` does not cover kube, db, app
  or desktop sessions. There is no all-protocol active-session panel here.
- **The SSH session count double-counts by design** (see above). Treat the
  per-job series as an upper bound, not a session inventory.
- **Certificate issuance is a bot-volume metric on this cluster.** It tells you
  nothing about human access, and a change in it most likely means a bot's
  renewal interval changed.
- **No per-user or per-resource attribution.** The Prometheus panels are
  cluster-wide aggregates and the two SQL panels count `user.login` events only.
  This board tells you *that* something happened, not *who* did it or *what* they
  reached. For that, query the audit log directly or use the Access Graph board.
- **Only `user.login` counts as a login.** MachineID `bot.join` and `cert.create`
  events are not logins and do not appear in the Authentication row, so a cluster
  whose access is entirely machine-driven will show an empty Authentication row
  and a busy Certificate Issuance row. That is correct, and it surprises people.
- **Two different clocks.** The audit database holds ~116 days; Prometheus holds
  ~7 usable days. Widen the time picker past a week and the Prometheus panels go
  blank while the SQL panels keep answering. Do not read the two side by side over
  a long window and conclude anything about the gap.
- **Connected resources over-counts under auth HA** (per-auth-instance gauge).
- **The gRPC panels cannot attribute traffic to a caller.** A `NotFound` storm
  will be visible but not blamed; `grpc_server_handled_total` carries no client
  identity.
- **No alert rules are attached.** Thresholds colour the panels; nothing pages.
- **Small-sample cluster.** Most of the numbers quoted above come from a nearly
  idle dev cluster. The structural conclusions (which metric is exported by which
  role, which suffix lies about its type) generalise; the magnitudes do not.
