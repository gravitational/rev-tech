# Teleport — Identity Security

This is the analyst board for Teleport Identity Security: 25 panels answering "who
can reach what in this cluster, through which grant path, and where is the policy
weak?" It is entirely a *posture* board, not an activity board — every panel except
one static text tile is live SQL against the Access Graph Postgres database, which
is a point-in-time model of the RBAC graph with no history. If you want "what
happened", use `teleport-identity` (audit + Prometheus). If you want "is posture
improving", use `teleport-executive`, which drills into this board. Audience is a
security engineer or IAM analyst doing an access review, or someone triaging a
Teleport-raised security alert.

## What it needs

| Requirement | Detail |
|---|---|
| Datasource `${DS_ACCESS_GRAPH}` | Postgres datasource pointing at the `access_graph` database. Provisioned in `helm/monitoring-values.yaml`. |
| Variable `$tenant` | Query variable: `SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'tenant_%'`. Every query opens with `SET search_path TO ${tenant};` — there is normally exactly one tenant schema per Teleport cluster. |
| Capability `accessGraph` | 24 of the 25 panels carry `x-requires: ["accessGraph"]`. The `MFA Coverage — Scope & Blind Spots` text panel carries `x-requires: []` and is the only thing that survives without it. |
| Teleport Enterprise | Access Graph / Identity Security is an Enterprise feature. There is no OSS equivalent of this data. |

Consequences on a deployment that lacks Access Graph: `scripts/render-dashboards.py`
**skips this file entirely** under both the `oss-postgres` and `cloud` profiles — the
board is not emitted at all rather than shipped as 24 empty panels. That is
deliberate; a stat tile with a dead datasource renders a large `0`, which on a
security board is indistinguishable from a real measurement of zero. See
`profiles/`.
The renderer also strips the executive board's drill-down link to this UID when the
profile skipped it, so `S5-dangling-link` stays clean.

UID `teleport-identity-security`. Tags `teleport`, `identity`, `access-graph` (it is
the one board in the set that does *not* carry `rev-tech`). Refresh 5m. The time
picker is hidden and the range is inert: the Access Graph carries no timestamps that
any of these queries filter on, so a time range would be a lie.

---

## Two structural facts about the Access Graph

Almost every design decision below follows from one of these. Read them first.

### 1. It cannot see SSO / login-rule grants

A role granted to a user by a **login rule** produces **no graph edge at all**. The
Access Graph models roles attached to a Teleport user resource; it does not model the
login-rule evaluation that happens at SSO login time.

Verified on this cluster: `jturner@b1tsized.tech` has **zero** `member_of` edges, while
audit `access_request.create` events record that user's standing `user_roles` as
`["role-base", "role-grafana-access", "role-kube-access-auto-approved"]`. Three real,
in-use roles, invisible to the graph.

The consequence is asymmetric and nasty: **any panel that infers "unused" or "nobody
holds this" from a missing edge produces false positives**, and those false positives
look exactly like findings. It also means per-user role counts under-report for every
SSO user. It does *not* affect panels that read node properties directly (resource
inventory, `require_mfa_type`, MFA device kind), because those do not traverse edges.

No query can fix this from the Access Graph alone. Confirm against login rules and the
audit log before acting on anything edge-derived.

### 2. It contains duplicate node rows

Access Graph keeps multiple node records for the same logical object — different
`source` / `origin_type` rows for one name — and **only one copy carries the
relationship edges** (and, for SSH actions, only one copy carries the logins list).
Measured on this cluster:

| Node kind | Rows | Distinct names |
|---|---|---|
| `identity_group` / `role` | 32 | 31 |
| `resource_group` | 9 | 5 |
| `action` / `ssh` | 8 | 7 |
| `action` / `app` | 8 | 7 |
| `action` / `database` | 6 | 5 |
| `action` / `kubernetes` | 6 | 5 |
| `action` / `desktop` | 4 | 3 |

So any `count(*)` or `count(DISTINCT node_id)` that should be
`count(DISTINCT value->>'name')` is inflated, and any join that walks row-by-row
instead of name-by-name will drop data that lives on a sibling row. Both failure modes
were present and both are fixed; the specific panels are called out below.

### 3. Preset and system roles are Teleport's, not yours

31 distinct roles break down as **14 `preset` + 4 `system` + 3 auto-generated `bot-*`
+ 10 operator-authored**. The label `teleport.internal/resource-type` distinguishes
them:

```sql
coalesce(value->'properties'->'teleport'->'labels'->>'teleport.internal/resource-type','')
  NOT IN ('preset','system')
AND value->>'name' NOT LIKE 'bot-%'
```

Teleport's presets hold wildcard access and sit unused **by design**. Counting them
measures Teleport's shipped defaults, not the customer's policy — so several panels
were measuring the wrong thing entirely. This filter now scopes *Operator-Created
Roles*, *Operator Roles w/o Graph-Visible Grant Path* (both copies), *Wildcard-Access
Roles*, *Access Request Escalation Paths* and *Reviewers Per Role*. It replaced two
earlier hardcoded exclusion lists (`NOT IN ('requester','okta-requester')` and
`LIKE 'role-%'`), so new Teleport presets are excluded automatically instead of
requiring a list edit — and the `LIKE 'role-%'` version had been silently dropping the
operator roles `admin-admin` and `ci-bot-role`.

---

## Panels

### Row: Summary — 6 stats

| Panel | Question | Why it is built this way |
|---|---|---|
| **Human Users** | How many interactive users? | Access Graph has **no `is_bot` flag**. The split is a naming heuristic: not `@%` and not `bot-%`. `localtest`, a leftover test account, is counted as human because nothing in the graph marks it otherwise. |
| **Bots / Service Identities** | How many machine identities? | Same heuristic, inverted. A service account named outside the convention is miscounted as human. |
| **Operator-Created Roles** | How many roles did *we* write? | `count(DISTINCT value->>'name')` with the preset/system/`bot-*` filter → **10**. The previous query counted rows over all roles and read **32**, which is both the wrong population and inflated by the duplicate row. |
| **Teleport Built-in Roles** | How many are Teleport's? | The complement — 14 preset + 4 system + 3 `bot-*` = **21**. Shown next to the operator count so the split is explicit rather than folded into one meaningless total. Neutral colour; it is context, not a finding. |
| **Resources** | Size of the protected estate. | `count(*)` on `kind='resource'`. Resource nodes are not duplicated, so a plain count is correct here. |
| **Active Security Alerts** | Is Identity Security telling us something right now? | See below — this was the worst defect found anywhere in the set. |

**Active Security Alerts — the green zero.** The panel filtered `status='OPEN'`. That
string **never occurs in this schema**: the only statuses emitted are `in_progress` and
`resolved`. So the tile read a green `0` while **22 high-severity alerts were live** —
9 connector updates, 8 role changes, 5 SSH sessions, all `severity=high`,
`status=in_progress`. The *Active Security Alerts* table at the bottom of the same
dashboard listed all 22, directly contradicting the KPI above it. A security dashboard
suppressing a real signal is worse than no dashboard. The predicate is now
`lower(status) NOT IN ('resolved','dismissed','closed')` — matching on *not-closed*
rather than guessing the open label, which also survives a schema that adds a new open
state. Red at ≥1.

### Row: Risk Indicators — 6 stats

**Users w/ Standing Privileges** — count of users with `standing_privileges > 0`.
Standing access is always-on access requiring no request. Under-counts SSO users for
reason (1). Orange at 1, red at 5.

**MFA, three panels instead of one.** The original single "Users w/o MFA" stat used
`weakest_mfa_device_kind IN ('UNSET','')` and was **inverted in practice**. Actual
values across the 5 user nodes: `TOTP` for two users, the literal `'UNSET'` for the bot
and the `localtest` account, and — for the SSO user — **the key is absent from the
properties object entirely**. So the old predicate flagged exactly the two non-humans
and silently skipped the one human with no Teleport-registered device. The states are
now separated, and only one of them is red:

- **Users w/ an MFA Device** — `NOT IN ('UNSET','')`. Green.
- **Users w/o an MFA Device** — `IN ('UNSET','')`, i.e. the graph knows and the answer
  is no. **Red at ≥1. This is the only one of the three that is a finding.**
- **Users w/ MFA Status Unknown** — `NOT (value->'properties' ? 'weakest_mfa_device_kind')`.
  Absence of data, not absence of MFA. Neutral blue, never red. On this cluster this is
  `jturner@b1tsized.tech`, a Google OIDC user whose second factor is enforced at the
  IdP; counting them as "no MFA" would be a false finding. Verify their posture in the
  IdP, not here.

**Operator Roles w/o Graph-Visible Grant Path** — the panel formerly titled "Dead
Roles". It reported **17**. The true number of dead roles is **0**.

- 14 of the 17 were Teleport preset/system roles, shipped unused by design.
- The remaining 3 were `role-base`, `role-grafana-access` and
  `role-kube-access-auto-approved` — *exactly* the three roles the SSO user holds via
  login rule. All three are false positives from the edge blindness in (1).

The query now excludes presets/system/`bot-*` and aggregates by role **name** (a
correlated `NOT EXISTS` over `nodes r2` matched on name, not on `r.id`) so the duplicate
row that carries no edges cannot make a live role look orphaned. It also dropped an
earlier `NOT EXISTS reviewer_of` clause that made the panel always return zero rows,
because `@teleport-access-approver` has a `reviewer_of` edge to every role.

**This remains a partial fix, and the title says what it measures rather than what it
concludes.** It is a review prompt, not a delete list. Neutral blue, deliberately not
red. Confirm against login rules and `access_request.create` audit events before
removing any role.

**Bots w/ Impersonation Rights** — `count(DISTINCT from_node)` on `impersonator_of`
edges. Bot impersonation confers the *full* permission set of the target role on a
machine identity, so this is the one bot number worth a tile.

### Row: User & Identity Details — 3 tables

**Users — Standing Privileges & MFA.** Per-user standing score, role count, weakest MFA
device. `roles_count` comes from `identity_groups`, which is edge-derived, so
`jturner@b1tsized.tech` reads **0** while actually holding three roles. Read 0 for an
SSO user as *unknown*, not *none*. `mfa` coalesces the absent property to `(unknown)`
so the SSO case is visibly different from `UNSET`. The `crown_jewel` and `locked`
columns were removed: both are `false` for every user here and a column that is
constant is noise.

**Standing SSH Access.** Who can SSH where, as which UNIX user, without an access
request. This is the panel most damaged by duplicate rows: Access Graph holds 8
`action`/`ssh` rows for 7 distinct actions and only one row per role carries
`ssh.logins.original_values`. The original query joined row-by-row, so for the *same
role* `olu` showed `logins = NULL` while `admin` showed `["root","ubuntu"]`. Logins are
now pre-aggregated in a `role_logins` CTE that unions
`jsonb_array_elements_text(...original_values)` across every duplicate row grouped by
role name, then left-joined on name. Both users now correctly read `root, ubuntu`.

Two gaps are expected and documented in the panel: `jturner@b1tsized.tech` is absent
(login-rule grant, no `member_of` edge), and `role-ssh-root-access` never appears
because nobody holds it as a standing role — it is request-only, and shows up in
*Access Request Escalation Paths* instead.

**Bot Impersonations.** The detail behind the impersonation stat: which bot can
impersonate which role.

### Row: Access Request & Reviewer Topology — 2 tables

**Access Request Escalation Paths.** A `requester_of` edge points at either another
role (a genuine privilege escalation target) *or* a `resource_group` (a label selector
bounding which resources may be requested via search-as-roles). These are completely
different things and the original panel put both in one `can_request` column, so a row
reading `role-base → {"*":"*"}` parsed as "role-base can request any role" when it
actually means "role-base may request resources matching any label". The query now
splits on the target node's `kind` into two columns — `can_request_role` and
`can_request_resource_scope` — so no reader has to know that `{"tier":"ops"}` is a
selector and not a role name.

**Reviewers Per Role.** This looks like a per-role approval policy table and is not
one. Every row's reviewer is the same single system role, `@teleport-access-approver`,
which holds 36 `reviewer_of` edges covering all 31 roles. The flat `reviewers` column
made a blanket grant look like ordinary per-role coverage. A `wildcard_reviewer`
boolean now computes, per reviewer, whether its distinct target count reaches the total
role count, and surfaces `true` — which on this cluster is every row. One identity can
approve anything; that should be legible at a glance.

**Limitation it still has:** the Access Graph does not record access-request
*auto-approval*. A role auto-approved by the approval bot and a role that genuinely
requires a human look identical here. Distinguish them with `access_request.review`
audit events.

### Row: Resources & Blast Radius — 3 tables

**Resource Inventory.** Every `kind='resource'` node with subkind and labels. Used to
verify expected coverage and spot unlabelled resources that no label-scoped role can
reach.

**Blast Radius (Top 25 Roles).** The old ranking was **meaningless**. It counted
DISTINCT `resource_group` *node IDs*, and since Access Graph holds 9 resource_group
rows for 5 distinct selectors, that number measured duplication rather than scope —
and by distinct selector *name* it equalled **1 for every single role**. So
`role-kube-access`, a wildcard over every Kubernetes cluster in the estate, tied
`role-grafana-access`, which reaches two named apps. The ranking is now:

```sql
ORDER BY has_wildcard DESC, resources_reachable DESC, role
```

with `has_wildcard = bool_or(rg.value->>'name' = '{"*":"*"}')` and
`resources_reachable = count(DISTINCT res.value->>'name')` over an extra hop from
resource_group to the actual resources. That does discriminate: the wildcard roles now
sort above `role-grafana-access` even though `role-grafana-access` reaches more
resources by raw count.

The wildcard flag is the **primary** sort key on purpose. `resources_reachable` counts
only resources *currently registered*; a wildcard role reaching one resource today
reaches every resource added tomorrow. Ranking on the count alone would rank a
time-limited snapshot rather than the actual privilege.

**Wildcard-Access Roles.** Operator roles holding *standing* access to `{"*":"*"}`.
Went from **8 rows to 2** via two independent corrections:

1. Five of the eight were Teleport presets — `access`, `require-trusted-device`,
   `list-access-request-resources`, `requester`, `terraform-provider` — which hold
   wildcards by design and drowned the operator-authored ones.
2. The edge walk was not pinned to `kind='access'`, so it also followed `requester_of`
   edges and listed `role-base`. `role-base` can only *request* wildcard-scoped
   resources; it holds no standing wildcard access. Requestable scope belongs in
   *Access Request Escalation Paths*, and that is where it now is.

### Row: Policy Hygiene — 1 stat, 1 text panel, 2 tables

**Roles Enforcing Session MFA.** Reads **0**, and the thresholds are inverted (red at
null, green at ≥1) so zero is red. Verified live: **all 35 `action` nodes carry
`require_mfa_type = 'OFF'`**. Nothing on this cluster forces a second factor at session
start.

**MFA Coverage — Scope & Blind Spots** (text panel, no datasource). The only panel that
renders without Access Graph. It states in the UI what this board can and cannot say
about MFA: enrolment (yes, three-way split), per-role enforcement (yes, all `OFF`),
cluster-wide policy (**no** — see *Known limitations*).

**Per-Role Session MFA Enforcement.** Every role's actions with their
`require_mfa_type` and `trusted_device`. **The `<> 'OFF'` filter was removed
deliberately.** With it, the panel returned exactly one row — `require-trusted-device`,
reading `mfa = OFF` — which looked like a populated, working panel and hid the actual
finding. (The 5 rows that *do* lack the property are the `can_request`/`can_review`
actions, coalesced to `(n/a)`.) Showing all 35 rows and letting the column read `OFF`
all the way down is the honest presentation. Cross-reference with *Wildcard-Access
Roles*: the widest roles have no MFA re-auth requirement.

**Operator Roles w/o Graph-Visible Grant Path** (table). Same query as the stat, with
the role description, so the review prompt names names.

### Row: Security Alerts — 1 table

**Active Security Alerts** (table). All alerts, newest first, limit 50. `severity` and
`status` are the leading columns with `color-background` cell mappings
(critical/high → red, medium → orange, low → yellow). `title` and
`affected_entity` are lifted out of the `data` JSONB so a row is readable without
expanding the blob; the full structured finding is still in the `data` column.

Alerts are triaged and closed **inside Teleport** (Identity Security → Security
Alerts), not in Grafana. Both alert panels say so.

---

## Decisions

**Every panel description carries its own SQL.** Each `description` ends with the
panel's `rawSql` in a fenced block, so hovering the info icon in Grafana gives you the
exact query to copy and adapt for ad-hoc analysis. This is duplicated state — the SQL
appears twice per panel, once in `targets[].rawSql` and once in prose — and it will
drift if someone edits one and not the other. It was judged worth it: the queries are
long, non-obvious JSONB traversals and this is an analyst board where "run a variant of
this by hand" is the normal next step.

**The two structural caveats are repeated per panel, not centralised.** The dashboard
`description` states both, and every affected panel restates the relevant one in its
own description. Grafana users land on a panel, not on a dashboard description nobody
reads. Redundancy beats a caveat that never gets seen.

**Count DISTINCT names, never rows or node IDs.** Non-negotiable given fact (2). Where
a join is unavoidable, join on `value->>'name'`, not on `id`.

**Panels are titled by what they measure, not by what they conclude.** "Dead Roles"
became "Operator Roles w/o Graph-Visible Grant Path" because the query cannot establish
deadness — only the absence of a visible grant path. Longer titles, but nobody deletes
a live role off the back of one.

**Findings are red; context and unknowns are not.** *Users w/ MFA Status Unknown* is
blue; *Teleport Built-in Roles* is neutral text; *Operator Roles w/o Graph-Visible
Grant Path* is blue despite sounding alarming. Only *Active Security Alerts*, *Users
w/o an MFA Device*, *Users w/ Standing Privileges* and *Roles Enforcing Session MFA*
(inverted) colour red. Colouring a known-false-positive red trains people to ignore red.

**Prefer a full table over a filtered one when the finding is the uniformity.** Both
*Per-Role Session MFA Enforcement* and *Active Security Alerts* previously filtered to
"interesting" rows and, in doing so, hid the answer. If every row says `OFF`, show
every row.

**Label filters over hardcoded name lists.** `teleport.internal/resource-type` and the
`bot-` prefix, not enumerated role names — the enumerations were already stale.

**Time range is hidden.** `timepicker.hidden: true`, range pinned to `now-1h` and
unused by every query. Access Graph is a current-state model; an adjustable time
picker that changes nothing is a trap.

## Known limitations

- **Login-rule / SSO grants are invisible.** Everything edge-derived — role counts,
  standing SSH access, grant-path detection — under-reports for SSO users. Not fixable
  from the Access Graph. Cross-check with login rules and `access_request.create`
  audit events.
- **Duplicate nodes are worked around, not solved.** The queries dedupe by name. A
  future Access Graph schema change could shift where properties live between duplicate
  rows and break the workaround silently.
- **No history.** The Access Graph is a snapshot. This board cannot show trend, drift,
  or "when did this role gain wildcard access". There is no period-over-period anything
  here and there cannot be.
- **No cluster-wide MFA policy, and it can never be here.**
  `cluster_auth_preference.second_factor` (currently `otp`, no WebAuthn) lives in the
  Teleport backend and is **API-only** — it is in no Postgres schema wired into this
  Grafana, and the `auth_preference.update` audit event records only
  `admin_actions_mfa_changed`, a boolean about admin-action MFA, not the second-factor
  value. It is surfaced on **`teleport-executive`** via the `teleport-usage` exporter,
  which reads it from the Teleport API. Until then, `tctl get cluster_auth_preference`.
- **Auto-approval is indistinguishable from human review.** *Reviewers Per Role* cannot
  tell you whether `@teleport-access-approver` is a bot rubber-stamping requests or a
  human. Use `access_request.review` audit events.
- **Identity denominators are polluted.** 5 user nodes = 1 bot + 1 `localtest` test
  account + 1 local admin + 2 humans. There is **no reliable bot flag** in the Access
  Graph; the `@` and `bot-` name prefixes are the only signal and they miss `localtest`
  entirely. Every per-user ratio on this board — and the MFA coverage ratio on the
  executive board — inherits that error. On a cluster of 5 this matters a lot; on a
  cluster of 5000 it is noise. Know which one you are on.
- **`resources_reachable` is a snapshot count**, not a bound. A wildcard role's blast
  radius is "everything, forever", regardless of what number the column shows today.
- **Alerts are read-only here.** No triage, acknowledge or close from Grafana. This
  board tells you to go to Teleport.
