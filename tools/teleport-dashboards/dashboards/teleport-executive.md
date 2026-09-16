# Teleport — Executive Summary

The entry point to the dashboard set. It answers a Security Director's question — *is our
access-control posture improving, is it covering the estate, and can we prove it?* — and
deliberately not *what does it cost*. Every tile drills into one of the analyst boards.

It is the only dashboard that composes from all four data sources, which is why it is also the
only one that survives, partially, on deployments where the others cannot run at all.

---

## What it needs

| Capability | Panels | If absent |
|---|---|---|
| `usageExporter` | 5 | Posture and TPR panels omitted |
| `accessGraph` | 5 | Posture row and role inventory omitted (Enterprise only) |
| `audit.postgres` | 4 | Activity panels omitted |
| `prometheus` | 2 | Assurance panels omitted |

Datasources: `DS_PROMETHEUS`, `DS_ACCESS_GRAPH`, `DS_TELEPORT_BACKEND`.

Rendered per profile by `scripts/render-dashboards.py`:

| Profile | Panels |
|---|---|
| `full-enterprise` | 17 of 17 |
| `oss-postgres` | 11 — no Access Graph |

**Panels are omitted, never left empty.** A stat tile drawing a large `0` because its datasource is
absent is indistinguishable from a real measurement of zero. On a board people make decisions from,
that is worse than the panel not being there.

---

## How to read it

Every tile carries a **confidence label** in its description:

| Label | Meaning |
|---|---|
| **Measured** | Directly counted from Prometheus, the Access Graph, or the Teleport API. |
| **Approximate** | Derived by classifying audit events, or measuring a proxy. Investigative, not billing-grade. |
| **Authoritative** | From the system of record. Nothing here qualifies yet. |

---

## Panels

### Posture — are we getting safer?

**Standing Privilege Ratio (humans)** · Access Graph · *Measured*
Percentage of human users holding privileged access standing rather than earning it just-in-time.
The single best measure of whether Teleport is delivering zero-trust value. Bot and system
identities (`@…`, `bot-…`) are excluded — including them dilutes the ratio with identities that are
*supposed* to hold standing grants.

**MFA Device Enrolled (humans)** · Access Graph · *Approximate*
Deliberately **not** called "MFA coverage". It measures device enrolment *in Teleport*, which is a
different thing. An SSO user whose IdP enforces MFA has no Teleport-registered device and is counted
here as not-enrolled. `weakest_mfa_device_kind` also reports the *weakest* registered factor, so an
all-OTP fleet scores 100%.

**Over-Permissioned Roles (created)** · Access Graph · *Measured*
Share of **operator-authored** roles granting wildcard (`*:*`) access. Teleport's presets hold
wildcards by design, so counting them measured Teleport's defaults rather than your policy. Of 31
roles only 10 are operator-authored; scoping to those changed the figure from 25% to 30% and made it
mean something.

**Roles: Operator-Created** · Access Graph · *Measured*
The policy surface your team actually owns. Replaced a "Dead Roles" tile — see *Decisions*.

**Second Factors — inventory of what Teleport supports** · Exporter · *Measured*
All three second factors Teleport supports, listed whether or not configured, so a type that is off
is a visible gap rather than an inference. **WebAuthn reads green** — the strongest factor Teleport
verifies itself. **OTP reads amber** — accepted, but weaker than the WebAuthn available and unused.
**SSO reads blue, not amber**: SSO is not a factor Teleport checks. It delegates the entire ceremony
to the IdP, so its strength is whatever the IdP enforces — possibly hardware keys and device trust,
possibly SMS. Teleport cannot see which, so the honest reading is *unknown*, not *weak*. If SSO is in
use, audit the IdP's own policy; this tile cannot.

**Session MFA Required (cluster)** · Exporter · *Measured*
Whether a fresh MFA check is demanded before a privileged session, rather than only at login. Login
MFA proves who started the session; session MFA proves who is using it now, which is what limits the
value of a stolen one.

> These three MFA tiles answer different questions on purpose. A cluster can score well on enrolment
> and be weak on both others. On the reference cluster all three disagree: MFA is enforced, OTP-only,
> and demanded by no role.

### Role Inventory — what we authored vs what Teleport ships

**Role Inventory by Origin** · Access Graph · *Measured*
Every role split by origin using the `teleport.internal/resource-type` label: 14 `preset`, 4
`system`, 3 auto-generated `bot-*`, 10 operator-created. Conflating them makes every role-based ratio
meaningless. `Assigned (graph)` **undercounts** — roles granted to SSO users via login rules produce
no graph edge, so `0` there does not mean "safe to delete".

### Coverage & Adoption — are we getting what we bought?

**Estate Coverage** · Exporter ÷ operator-supplied · *Measured / manual*
Enrolled resources as a share of the known estate. The gap is the shadow estate. The denominator is
the hand-maintained `known_estate_size` variable — Teleport cannot know how big your estate is — and
the tile reads *Not configured* until it is set. The expression is gated so an unset denominator
returns nothing rather than `+Inf`, which Grafana would render as a real-looking value.

**Protected Resources (TPR)** and **by Kind** · Exporter · *Measured*
The figure billing is based on, read from the API rather than inferred. Three independent sources
agree on this cluster and the validator asserts two of them stay in agreement. Every kind is emitted
including zeros, so an unused kind is a visible zero rather than a missing bar.

**Human Active Users (period / by month)** · Audit log · *Approximate*
Bots excluded — they do not count toward billable MAU and including them would misrepresent adoption.
`user_kind` is known to be inconsistent, hence *Approximate*; the licence portal remains
authoritative.

**Protocol Mix (share / by month)** · Audit log · *Approximate*
Answers "did we buy a platform and deploy one protocol?" A stack that broadens is a rollout; one that
stays a single colour is an SSH replacement.

### Control-Plane Assurance — can we still prove what happened?

**Audit Continuity** · Prometheus · *Measured*
Three ways the record loses evidence: failed audit emits, S3 upload errors, and peak sessions pending
upload. Target is zero, so these are counts rather than ratios. Note
`teleport_incomplete_session_uploads_total` is a **gauge** despite its `_total` suffix and is read
with `max_over_time`, not `increase()`.

**Monitoring Target Availability** · Prometheus · *Approximate*
Scrape-target availability as a proxy for service availability. It does not distinguish a scrape
failure from an outage and carries no error budget; a real SLO with burn rate is a recording-rule job.
Requires a scrapeable Prometheus.

---

## Decisions

**No quarter-over-quarter arrows.** The Access Graph is a point-in-time model with no history, and
Prometheus retention here is 7 days. Deltas are omitted rather than faked from a short window. They
arrive with the rollup work.

**Prometheus windows come from `$prom_retention`, not the dashboard range.** Retention is a property
of the cluster you install on. A window longer than retention silently computes over whatever exists
and presents it as the longer period — the failure this variable exists to prevent. `audit_retention`
is separate and much longer: 7 days of Prometheus against 116 days of audit history on the reference
cluster. Collapsing them into one value would either truncate the audit panels or ask Prometheus for
data it discarded.

**No cost or licensing tiles.** Self-hosted Teleport exposes no programmatic read of your licensed
quota — that lives only in the licence portal
([teleport#62832](https://github.com/gravitational/teleport/issues/62832)). Entitlement utilisation,
forecast-to-breach and spend-per-resource are specced and appear once contract values are configured.

**A "Dead Roles" tile was removed as unsound.** It inferred disuse from missing graph edges, but roles
granted to SSO users through login rules create none. It reported 53% dead when the true figure was
approximately zero: of 17, fourteen were Teleport presets and the remaining three were false
positives. No query fixes this from the Access Graph alone.

**Posture tiles exclude bot and system identities.** Including them diluted every ratio. There is no
reliable bot flag on identity nodes — `@` and `bot-` name prefixes are the only signal, and they miss
a test account like `localtest`.

---

## Known limitations

- **Small denominators.** Four human identities and ten operator roles on the reference cluster. Read
  the trend, not the digit.
- **SSO blind spots.** The Access Graph cannot see login-rule grants, so standing-privilege and
  role-assignment figures undercount for SSO users.
- **No history.** Nothing here can show you last quarter.
- **Estate Coverage decays silently.** A hand-maintained denominator goes stale; `known_estate_updated`
  is shown in the tile title so staleness is at least visible.

## Not on this board, and why

| Tile | Status |
|---|---|
| Access Request SLA / Outcomes | **Ready to build.** Approvals are `access_request.update` with `state='APPROVED'`; this cluster emits no `access_request.review` events at all. Correlation key `id` confirmed. |
| RBAC Change Volume | **Ready to build**, roles only. `role.created` / `role.deleted` exist; `role.updated` and all `lock.*` do not. |
| Session Recording Coverage | **Blocked.** `teleport_session_starts_total` does not exist, and `session.upload` tracks app chunks rather than interactive sessions. Needs a different definition. |
| Adoption by Team | **Cut.** `user.login` carries no `user_traits` — 0 of 143 events, local and SSO alike. |
| Access List Review Compliance | Exporter — review schedules are not in the audit stream. |
| Dormant Identities & Resources | Exporter — roster and activity live in separate databases and cannot be joined in one panel. |
| CA rotation / certificate expiry | Exporter — API-only data. |
