# Teleport — Overview (TV)

`teleport-overview.json` · UID `teleport-overview` · 9 panels · default range **last 1h** · refresh **30s**

This is the wall board. It answers one question, for a room rather than a person: **is Teleport
up, is anyone using it, and is anything obviously wrong right now?** It is meant to be glanced at
from across a room during an ops huddle or left on a TV, so every panel is a single big number or
a gauge, there are no rows, no tables, no legends to read, and the whole thing fits on one screen
without scrolling. If you need to know *why* a number moved, this board deliberately cannot tell
you — go to `teleport-ops-health` (SRE detail) or `teleport-identity` (login and session detail).

Because it is a glance board, the bar for a panel here is higher than "the query returns
something". A tile that is silently wrong is worse than no tile, because nobody is going to
cross-check a wall display. Most of what follows is the record of tiles on this board that were
green and wrong.

## What it needs

**Datasources**

| Variable | Type | Purpose |
|---|---|---|
| `$datasource` | Prometheus | 7 of 9 panels |
| `$DS_TELEPORT_BACKEND` | Postgres | The two login tiles. Must reach the Teleport audit database (`teleport`, `SELECT` on `public.events`). Picked by the regex `/[Tt]eleport ?[Bb]ackend/`. |

**Capabilities (`x-requires`)**

| Capability | Panels | Which |
|---|---|---|
| `prometheus` | 4 | Cluster Status, Connected Resources, Active SSH Sessions, Audit Upload Errors |
| `kubeStateMetrics` | 3 | Worker Nodes Ready (kube-state-metrics), CPU and Memory (cAdvisor — the capability covers both) |
| `audit.postgres` | 2 | Logins Today, Failed Logins Today |

On a deployment that lacks one of these, `scripts/render-dashboards.py` **omits** the affected
panels rather than shipping them to render "No data" — an empty tile on a wall display reads as a
measurement of zero. Concretely:

- **No Postgres audit backend** (DynamoDB, Firestore, file): the two login tiles disappear and the
  board goes to 7 panels. There is no correct Prometheus substitute; see the two login panels below.
- **No kube-state-metrics / cAdvisor** (a non-Kubernetes install): the node and
  resource tiles disappear and the board goes to 6.
- **Neither Prometheus nor an audit database**: nothing on this board survives, and the renderer
  skips it rather than publishing an empty shell.

**Template variables**

- `$namespace`, `$teleport_job` — from `label_values(teleport_build_info, …)`, as on the other boards.
- `$expected_targets` — a **textbox**, currently `7` (auth, 2 proxies, ssh-node, grafana-agent,
  prometheus-agent, postgres). Not derived from anything, and it has to be updated by hand when you
  add or remove a scrape target. That is the price of the Cluster Status fix below.

## Panels

### 1. Cluster Status — `sum(up{namespace=~"$namespace"}) / $expected_targets`

*Are all the things that should be running, running?*

The obvious version, `avg(up{...})`, **cannot detect a target that disappears**. `avg` only
averages series that still exist. Scale a Deployment to zero and its `up` series stops being
emitted entirely; the survivors keep averaging 1.0 and the tile stays green through the exact
outage it exists to catch. Dividing an absolute `sum` by an expected count makes a vanished target
pull the fraction down.

It also used to be filtered by `$teleport_job`, which is derived from `teleport_build_info`. The
Postgres exporter does not emit `teleport_build_info`, so `job="teleport/teleport-postgres"` was
never in the variable's value set and **the audit database sat outside the cluster health check**.
The filter is gone; the panel is anchored on namespace instead.

Thresholds: green only at exactly `1`, orange at `0.9`, red below.

### 2. Connected Resources — `sum(max by (type)(teleport_connected_resources{...}))`

*How much of the estate is registered with Teleport?* Reads 4 today.

`teleport_connected_resources` is a **per-auth-instance** gauge: every auth replica reports the
whole cluster's inventory. A plain `sum()` is correct with one auth replica and silently multiplies
by N the day you scale auth for HA. `max by (type)` collapses the replicas first, then sums across
resource types. Same answer today, correct answer later.

### 3. Active SSH Sessions — `sum(proxy_ssh_sessions_total{...})`

*Is anyone connected right now?*

**Do not wrap this in `rate()` or `increase()`.** Despite the `_total` suffix, the metric metadata
confirms `proxy_ssh_sessions_total` is a **GAUGE** ("Number of active sessions through this
proxy"). Using it bare is correct; rate-ing a gauge of concurrent sessions is meaningless. This is
written here because the `_total` suffix is a standing invitation for the next editor to "fix" it.

It is also **SSH only**. Kubernetes, database, app and desktop sessions are counted nowhere on
this board.

### 4. Worker Nodes Ready — `sum(kube_node_status_condition{condition="Ready",status="true"} * on(node) group_left kube_node_role{role="node"})`

*Are the nodes Teleport runs on healthy?*

This is the best example on the board of a query that looks obviously right and **cannot report
the failure it exists to report**. The previous version was:

```promql
count(kube_node_status_condition{condition="Ready",status="true"})
```

kube-state-metrics emits all three condition values (`true`, `false`, `unknown`) for every node,
permanently. When a node goes NotReady, the `status="true"` series does not disappear — it stays
present with **value 0**. `count()` counts series, not values, so the tile never moves. It read
**2** when there was **1** worker, and it could never have gone down.

Two bugs in one line, in fact: it also counted the control-plane node on a tile whose title says
"Worker". `sum()` reads the values instead of counting the series, and the `group_left` join
against `kube_node_role{role="node"}` excludes the control plane.

Threshold is green at `1` because there is exactly one worker. **Raise it if you scale the nodes
instance group** — with 3 workers and this threshold, a dead node reads 2 and stays green.

### 5. Logins Today (24h) — SQL, `public.events`

```sql
SELECT count(*) FROM public.events
WHERE event_type = 'user.login' AND event_data->>'success' = 'true'
  AND event_time >= now() - interval '24 hours'
```

*How much human activity is there?*

Not sourced from `user_login_total`, which **over-reports by roughly 7x**: it incremented +7 over a
45-minute window on 2026-08-27 against exactly **one** `user.login` audit event, because it also
counts re-authentications and session refreshes. A wall tile reading 7x the truth is worse than no
tile.

If you specifically need a Prometheus-side activity signal (a deployment without a Postgres audit
backend), `teleport_user_certificates_generated` is trustworthy — its 7d increase was 2023 against
2023 `cert.create` audit events. It measures certificate issuance, not logins, so it is a different
question, honestly answered.

### 6. Failed Logins Today (24h) — SQL, `public.events`

Same query with `success = 'false'`. Green under 5, orange at 5, red at 10.

*Is someone failing to get in?*

The Prometheus version of this tile was **a permanently green zero for something it structurally
cannot see**. `failed_login_attempts_total` is exported only by `job="teleport"` (the proxies) and
`job="teleport/ssh-node"` — never by `teleport-auth`, which is where SSO and local logins are
actually evaluated. It is the SSH-server-side failed-auth counter, not a login-failure counter.

The evidence: the audit log holds **27** failed logins all-time (16 oidc, 11 local) while
`max_over_time(failed_login_attempts_total[7d])` is **0 on every series**. The tile reported "all
clear" for a signal that had never once reached it.

The audit query covers SSO (oidc/saml/github), local password and web login failures.

### 7. Audit Upload Errors (15m) — `sum(increase(audit_failed_emit_events{...}[15m]))`

*Are we losing the audit record?* Anything above 0 is red.

The query was already correct. The **labelling** was not: the title said 15m, the legend said 1h,
the description said "the last hour", and the query was `[15m]`. A responder trusting the
description would have under-reacted by 4x — assuming a count of 3 was spread over an hour when it
actually happened in fifteen minutes. Title, legend, description and query window now all say 15m.

### 8. CPU — Busiest Teleport Pod (cores) — `max(max by (pod)(rate(container_cpu_usage_seconds_total{namespace=~"$namespace",container="teleport"}[5m])))`

*Is anything working unusually hard?*

Previously an average across pods, which made the tile **structurally incapable of turning
orange**. The average sat at 0.0027 cores across 6 containers while auth ran at 0.0062, and the
thresholds were 0.5 / 0.9 cores — so one pod would have had to burn **3.0 cores** to push the
average past orange and **5.4** past red. On this cluster that will never happen; the tile was
decoration.

`max by (pod)` then `max` shows the busiest pod. Thresholds were then reset against measured
reality:

- 7d per-pod peak: **0.036 cores** (proxy).
- **Orange at 0.1** — about 3x observed peak.
- **Red at 0.25** — half of ssh-node's 500m limit, the only CPU limit in the namespace. Auth and
  the proxies have no limit, so "cores" here is not anchored to a budget for those pods.
- Gauge `max` is **0.5**, so normal load is actually visible on the dial instead of pinned at zero.

Scoped to `container="teleport"` and deliberately **not** filtered by `$teleport_job` — cAdvisor
metrics do not carry that label, so adding the filter would empty the panel.

### 9. Memory — Heaviest Teleport Pod — `max(max by (pod)(container_memory_working_set_bytes{namespace=~"$namespace",container="teleport"}))`

Same fix, same reason. The average read **62–77 MB** and hid `teleport-auth` at **215 MB**, roughly
3x the average, because the proxies sit near 60 MB and the agents near 40 MB. It also carried **no
thresholds at all**, so it could not have alerted anyone to anything.

- 7d per-pod peak: **215 MB** (auth).
- **Orange at 400 MB** — fires before ssh-node, the only container with a memory limit (512Mi),
  would be OOMKilled.
- **Red at 700 MB** — above that limit, so it catches a genuine runaway in an unlimited pod rather
  than restating an OOMKill you would find out about anyway.

## Decisions

**Both resource tiles were retitled.** Collapsing to `max` loses the pod name — the tile tells you
*something* is at 215 MB but not *what*. The titles say "Busiest" and "Heaviest" so nobody reads
the number as a total or a fleet average. If you need to know which pod, that is what
`teleport-ops-health` is for; adding a per-pod breakdown here would break the glance-ability that
is the whole point of the board.

**The board pays a real portability cost for correctness.** Moving the two login tiles to SQL is
why this dashboard now requires a Postgres datasource at all. That was a genuine conflict —
Prometheus-only dashboards travel to any cluster — and correctness won, because there is no correct
Prometheus source for login success and failure. The `audit.postgres` capability and the renderer
exist to contain the cost: on a non-Postgres backend the board loses two panels instead of being
wrong on two panels.

**The two SQL tiles stay single-value stats.** A SQL datasource makes tables and time series easy,
and both were tempting here. They are not on this board, because a table on a TV is unreadable and
because "9 tiles, one screen, no scrolling" is the constraint that makes the board useful. Login
history belongs on `teleport-identity`.

**Both SQL tiles use a fixed 24h window**, independent of the dashboard time picker. "Today" means
the same thing whether the board was left on 1h or someone zoomed to 6h. The time picker therefore
only affects the sparkline history behind the Prometheus tiles, not any headline number.

**Retention is not a constraint on this board, and does not need "fixing".** The longest window
anywhere here is 24h — Prometheus queries reach 15m at most, and the SQL tiles reach 24h against an
audit database holding 116 days. Prometheus retention (raised to 30d, with ~7d of data actually
accumulated as of 2026-09-01) is far more than this board asks for. Unlike the executive board,
this one has no `$prom_retention` variable and does not need one.

**`$expected_targets` is a hand-maintained constant.** Deriving it would defeat the point — any
expression computed from the series that currently exist has the same blind spot as `avg(up)`. A
number a human has to update is the only thing that notices something is missing.

## Known limitations

- **`$expected_targets` goes stale silently.** Add a scrape target and forget to bump it and the
  tile reads above 1.0 — which the panel's `max: 1` clamps back to a green 1.0. Remove one and the
  tile sits permanently orange. It has to be maintained by hand.
- **Worker Nodes Ready has a hardcoded green threshold of 1.** Scale the instance group and the
  threshold is wrong until someone edits it. The query is right; the colour is not automatic.
- **The `kube_node_role` join is a portability assumption.** It depends on workers carrying a
  `node-role.kubernetes.io/node` label, which kops sets. On a cluster where worker nodes have no
  role label the join matches nothing and the tile reads "No data" rather than counting the control
  plane — a visible failure, not a silent one, but a failure.
- **SSH sessions only.** Kubernetes exec, database, app and desktop sessions appear nowhere. A busy
  kube-heavy cluster can show 0 active sessions here and be perfectly healthy — or perfectly
  compromised.
- **CPU and memory are "the worst pod", not the fleet.** They cannot tell you two pods are
  simultaneously elevated, and they do not name the pod.
- **The board is a snapshot, not a trend.** Default range 1h, refresh 30s. It answers "right now".
  Nothing here shows week-over-week movement, and it should not — that is the executive board.
- **The login tiles measure `user.login` events, not sessions or unique users.** One person logging
  in five times reads 5.
- **`sum(up)` counts every target in the namespace**, including grafana-agent and prometheus-agent.
  A degraded telemetry pod drops Cluster Status off green even though Teleport itself is fine. That
  is intentional — you cannot trust the rest of the board if the scrapers are down — but it means
  the tile is "is the monitoring picture complete", not strictly "is Teleport up".
- **No alerting.** Nothing on this board pages anyone. Red is a colour on a TV; if nobody is looking
  at the TV, nothing happens.
