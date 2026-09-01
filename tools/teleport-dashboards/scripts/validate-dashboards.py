#!/usr/bin/env python3
"""
validate-dashboards.py — conformance test for the Teleport Grafana dashboards.

Runs every panel query in every dashboard against a live cluster and fails on the
failure modes that actually bit us, rather than on JSON syntax alone. The point is
that a panel returning a plausible number for the wrong reason is worse than a
panel returning nothing, and only executing the query against real data catches it.

Checks performed
----------------
STRUCTURAL (no cluster needed, --offline)
  S1  file parses as JSON
  S2  panel gridPos rectangles do not overlap
  S3  every ${var} referenced by a panel is declared in templating.list
  S4  every panel target names a datasource

SEMANTIC LINT (no cluster needed for most; PromQL metadata needs --prom)
  L1  rate()/increase()/irate() applied to a metric Prometheus reports as a gauge.
      Teleport ships several gauges with a `_total` suffix
      (teleport_incomplete_session_uploads_total, proxy_ssh_sessions_total),
      so the suffix is not a safe signal.
  L2  a range selector longer than Prometheus retention. Silently computes over
      whatever exists and presents it as the requested window.
  L3  count() over a kube-state-metrics *_condition series. kube-state emits one
      series per condition value permanently, so count() counts series, not things,
      and cannot decrease when the condition flips.
  L4  a metric name that returns no series at all.

CROSS-SOURCE (needs cluster; see corroborations.json)
  C1  two independent sources that measure the same quantity must agree.
      D1-D3 cannot catch a datastore that is confidently wrong: a collector
      whose credentials expired and which then recorded zeros returns a row,
      not empty and not NaN. Only a second opinion detects that.

LIVE (needs cluster)
  D1  every query executes without error
  D2  result is not empty
  D4  result falls outside the panel's own declared min/max. Grafana clamps to
      the bound, so a stale denominator renders as a plausible number.
  D3  result is neither NaN nor Inf. 0/0 and x/0 both render as plausible
      values in Grafana and mislead identically.

Usage
-----
  ./validate-dashboards.py                        # all dashboards, live
  ./validate-dashboards.py --offline              # structural + static lint only
  ./validate-dashboards.py dashboards/x.json      # one file
  ./validate-dashboards.py --prom http://localhost:9090
  ./validate-dashboards.py --corroborate ''   # skip the cross-source checks

C1 runs only on a full-set run (no file arguments), because it checks
datasources rather than dashboards.

Exit code is non-zero if any ERROR-level finding is present. WARN does not fail.

Self-test
---------
  ./validate-dashboards.py scripts/testdata/dashboard-selftest.json

That fixture contains one deliberately broken panel per check, drawn from bugs
that were actually found in these dashboards. It must report exactly 9 errors
(S2, S3, S5, S6, L1, L2, L3, D3, D4). If it reports fewer, a check has regressed and the
harness is no longer protecting you — fix the harness before trusting a pass.

Postgres queries are executed via `kubectl exec` into the CNPG pod, so the
datasource name in the dashboard is mapped to a database by DB_FOR_DATASOURCE
below. Adjust that map (and PG_POD/TENANT_SQL) when this moves to another repo.
"""

from __future__ import annotations
import argparse, json, math, os, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
from dataclasses import dataclass, field

# ---------------------------------------------------------------- environment

PROM_DEFAULT = os.environ.get("PROM_URL", "http://localhost:9090")

# SQL panels are executed by shelling into a Postgres pod, because that needs no
# credentials of its own. Override for a differently-named cluster.
PG_NS = os.environ.get("TELEPORT_PG_NAMESPACE", "teleport")
PG_POD = os.environ.get("TELEPORT_PG_POD", "teleport-postgres-1")
PG_CONTAINER = os.environ.get("TELEPORT_PG_CONTAINER", "postgres")

# Grafana datasource name (as pinned in the dashboard) -> Postgres database.
DB_FOR_DATASOURCE = {
    "DS_ACCESS_GRAPH": "access_graph",
    "DS_TELEPORT_BACKEND": "teleport",
    "DS_USAGE": "usage",
}
TENANT_SQL = ("SELECT schema_name FROM information_schema.schemata "
              "WHERE schema_name LIKE 'tenant_%' ORDER BY 1 LIMIT 1;")

SEV_ERROR, SEV_WARN, SEV_OK = "ERROR", "WARN", "OK"


@dataclass
class Finding:
    severity: str
    dashboard: str
    panel: str
    check: str
    detail: str


@dataclass
class Ctx:
    prom: str
    offline: bool
    retention_s: float | None = None
    meta: dict = field(default_factory=dict)      # metric -> type
    actual_s: float | None = None
    prom_ok: bool = False
    prom_unreachable: int = 0
    tenant: str | None = None
    findings: list = field(default_factory=list)

    def add(self, sev, dash, panel, check, detail):
        self.findings.append(Finding(sev, dash, panel, check, detail))


# ---------------------------------------------------------------- helpers

def sh(cmd: list[str], stdin: str | None = None) -> tuple[int, str]:
    p = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def prom_get(ctx: Ctx, path: str, params: dict, _retries: int = 3) -> dict | None:
    """GET from Prometheus, retrying transient transport failures.

    A dropped connection (port-forward blip, pod roll) otherwise surfaces as a
    D1-query-error on every panel, which is indistinguishable from a genuinely
    broken query. A validator that intermittently invents findings is worse than
    one that runs less often, because people learn to ignore it.
    """
    url = f"{ctx.prom}{path}?{urllib.parse.urlencode(params)}"
    last = None
    for attempt in range(_retries):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                ctx.prom_ok = True
                return json.load(r)
        except urllib.error.HTTPError as e:
            # A 4xx/5xx is Prometheus answering: a real query error, not transport.
            try:
                return json.load(e)
            except Exception:
                last = e
                break
        except Exception as e:
            last = e
            if attempt < _retries - 1:
                time.sleep(1.5 * (attempt + 1))
    ctx.prom_unreachable += 1
    return None


DUR = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800, "y": 31536000}


def dur_to_s(text: str) -> float:
    total, num = 0.0, ""
    for ch in text:
        if ch.isdigit():
            num += ch
        elif ch in DUR and num:
            total += int(num) * DUR[ch]
            num = ""
    return total


def load_prom_context(ctx: Ctx) -> None:
    """Retention and metric-type metadata: the two things static analysis can't know."""
    flags = prom_get(ctx, "/api/v1/status/flags", {})
    if flags:
        for key in ("storage.tsdb.retention.time", "storage.tsdb.retention"):
            v = (flags.get("data") or {}).get(key)
            if v and v not in ("0s", "0"):
                ctx.retention_s = dur_to_s(v)
                break
    # Configured retention is a ceiling, not a promise. A cluster whose retention
    # was just raised from 7d to 30d still holds only 7 days, and a 30d window
    # over it silently computes on what exists and labels it a month -- the exact
    # failure L2 exists to catch. Use the LESSER of configured retention and the
    # age of the oldest sample actually present.
    r = prom_get(ctx, "/api/v1/query", {"query": "min_over_time(timestamp(up)[365d:1h])"})
    res = ((r or {}).get("data") or {}).get("result") or []
    if res:
        # One result per `up` series, and the vector order is not stable. Taking
        # res[0] picks an arbitrary series: a pod that restarted minutes ago has
        # an `up` series minutes old, which computed an effective retention of
        # 0.0d and made every window look over-long. The oldest sample across
        # ALL series is the real history depth.
        oldest = min(float(x["value"][1]) for x in res if x.get("value"))
        actual = time.time() - oldest
        ctx.actual_s = actual
        ctx.retention_s = min(ctx.retention_s, actual) if ctx.retention_s else actual
    md = prom_get(ctx, "/api/v1/metadata", {})
    for name, entries in (((md or {}).get("data")) or {}).items():
        if entries:
            ctx.meta[name] = entries[0].get("type", "")


def get_tenant(ctx: Ctx) -> str | None:
    if ctx.tenant or ctx.offline:
        return ctx.tenant
    rc, out = sh(["kubectl", "-n", PG_NS, "exec", PG_POD, "-c", PG_CONTAINER, "--",
                  "psql", "-U", "postgres", "-d", "access_graph", "-t", "-A", "-c", TENANT_SQL])
    if rc == 0:
        for line in out.splitlines():
            if line.strip().startswith("tenant_"):
                ctx.tenant = line.strip()
                break
    return ctx.tenant


# ---------------------------------------------------------------- extraction

VAR_RE = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")
METRIC_RE = re.compile(r"\b([a-z_][a-z0-9_]*(?:_total|_seconds|_bytes|_count|_sum|_bucket)?)\s*(?:\{|\[)")
RANGE_RE = re.compile(r"\[([0-9]+[smhdwy]+)(?::[0-9a-z]*)?\]")
FUNC_ON_METRIC_RE = re.compile(r"\b(rate|irate|increase)\s*\(\s*([a-zA-Z_:][a-zA-Z0-9_:]*)")
KUBE_COND_COUNT_RE = re.compile(r"\bcount\s*\(\s*(kube_[a-z_]*_condition)")
LINK_UID_RE = re.compile(r"/d/([A-Za-z0-9_-]+)")

# Datasource types a cluster commonly has more than one of, where autobinding
# picks silently and wrongly. Prometheus is usually singular, so it is omitted.
AMBIGUOUS_DS_TYPES = {"postgres", "mysql", "grafana-postgresql-datasource", "loki", "elasticsearch"}

GRAFANA_BUILTINS = {"__range", "__interval", "__rate_interval", "__interval_ms",
                    "__from", "__to", "__timeFilter", "__timeFrom", "__timeTo",
                    "__timeGroup", "__timeGroupAlias", "__name__", "__auto"}

# Prometheus synthesises these per scrape; they never appear in /api/v1/metadata.
SYNTHETIC_METRICS = {"up", "scrape_duration_seconds", "scrape_samples_scraped",
                     "scrape_samples_post_metric_relabeling", "scrape_series_added",
                     "scrape_body_size_bytes", "ALERTS", "ALERTS_FOR_STATE"}
PROMQL_KEYWORDS = {"le", "vector", "sum", "avg", "max", "min", "count", "on", "by",
                   "without", "group_left", "group_right", "ignoring", "offset",
                   "bool", "and", "or", "unless", "topk", "bottomk", "quantile"}


def iter_panels(dash: dict):
    for p in dash.get("panels", []):
        yield p
        for sp in p.get("panels", []) or []:
            yield sp


def declared_vars(dash: dict) -> set[str]:
    return {v.get("name") for v in (dash.get("templating", {}).get("list") or [])}


def ds_var_of(obj: dict) -> str | None:
    uid = ((obj or {}).get("datasource") or {}).get("uid") or ""
    m = VAR_RE.fullmatch(uid.strip())
    return m.group(1) if m else None


# ---------------------------------------------------------------- checks

def check_structure(ctx: Ctx, name: str, dash: dict) -> None:
    # S2 overlap
    rects = []
    for p in dash.get("panels", []):
        g = p.get("gridPos") or {}
        rects.append((g.get("x", 0), g.get("y", 0), g.get("w", 0), g.get("h", 0), p.get("title", "?")))
    for i in range(len(rects)):
        ax, ay, aw, ah, at = rects[i]
        for j in range(i + 1, len(rects)):
            bx, by, bw, bh, bt = rects[j]
            if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                ctx.add(SEV_ERROR, name, at, "S2-overlap", f"overlaps {bt!r}")

    decl = declared_vars(dash)
    for p in iter_panels(dash):
        title = p.get("title") or f"(id {p.get('id')})"
        if p.get("type") == "row":
            continue
        for t in p.get("targets", []) or []:
            if not t.get("datasource"):
                ctx.add(SEV_WARN, name, title, "S4-datasource", "target has no datasource")
            body = t.get("expr") or t.get("rawSql") or ""
            for v in VAR_RE.findall(body):
                if v not in decl and v not in GRAFANA_BUILTINS:
                    ctx.add(SEV_ERROR, name, title, "S3-undeclared-var", f"${{{v}}} not in templating.list")


def _eval_source(ctx: Ctx, src: dict) -> tuple[float | None, str | None]:
    """Evaluate one side of a corroboration. Returns (value, error)."""
    kind = src.get("kind")
    if kind == "constant":
        return float(src["value"]), None
    if kind == "promql":
        r = prom_get(ctx, "/api/v1/query", {"query": src["query"]})
        if r is None or r.get("status") != "success":
            return None, f"promql failed: {(r or {}).get('error', 'request failed')}"
        res = (r.get("data") or {}).get("result") or []
        if not res:
            return None, "promql returned no series"
        try:
            return float(res[0]["value"][1]), None
        except (KeyError, ValueError) as e:
            return None, f"unparseable promql result: {e}"
    if kind == "sql":
        q = src["query"]
        # Corroboration SQL gets the same tenant substitution the dashboard path
        # does. Without it an Access-Graph query fails to parse, and because the
        # spec sets skip_if_b_missing it would skip SILENTLY -- a check that is
        # not running while appearing to pass is the failure mode this whole
        # harness exists to prevent.
        tenant = get_tenant(ctx)
        if tenant:
            q = q.replace("${tenant}", tenant).replace("$tenant", tenant)
        q = q.rstrip().rstrip(";") + ";"
        rc, out = sh(["kubectl", "-n", PG_NS, "exec", "-i", PG_POD, "-c", PG_CONTAINER, "--",
                      "psql", "-U", "postgres", "-d", src.get("db", "teleport"),
                      "-t", "-A", "-v", "ON_ERROR_STOP=1", "-f", "-"], stdin=q)
        if rc != 0:
            first = next((l for l in out.splitlines() if "ERROR" in l), out.strip()[:120])
            return None, f"sql failed [{src.get('db')}]: {first}"
        rows = [l.strip() for l in out.strip().splitlines() if l.strip() and not l.startswith("SET")]
        if not rows or rows[0] == "":
            return None, "sql returned no rows"
        try:
            return float(rows[0]), None
        except ValueError:
            return None, f"non-numeric sql result: {rows[0][:40]!r}"
    return None, f"unknown source kind {kind!r}"


def run_corroborations(ctx: Ctx, path: str) -> None:
    """Cross-check quantities that two independent sources both claim to measure.

    This exists because D1-D3 cannot catch a datastore that is confidently
    wrong. A collector whose credentials expired and which then recorded zeros
    produces a query that succeeds, returns a row, and is neither empty nor
    NaN — indistinguishable from a real measurement of zero. The only way to
    detect it is to ask a second source and compare.
    """
    if not os.path.exists(path):
        return
    try:
        specs = json.load(open(path))
    except Exception as e:
        ctx.add(SEV_ERROR, os.path.basename(path), "-", "C1-config", f"unreadable: {e}")
        return

    for spec in specs:
        nm = spec.get("name", "?")
        sev = SEV_ERROR if spec.get("severity", "ERROR") == "ERROR" else SEV_WARN
        av, aerr = _eval_source(ctx, spec["a"])
        bv, berr = _eval_source(ctx, spec["b"])

        if berr and spec.get("skip_if_b_missing"):
            ctx.add(SEV_OK, "corroboration", nm, "C1-skipped",
                    f"second source unavailable ({berr}) — not a disagreement, but nothing is cross-checking "
                    f"{spec['a'].get('label', 'source A')} either")
            continue
        if aerr or berr:
            ctx.add(sev, "corroboration", nm, "C1-eval-error", aerr or berr)
            continue

        if spec.get("comparison") == "b_at_most_a":
            if bv > av:
                ctx.add(sev, "corroboration", nm, "C1-threshold",
                        f"{spec['b'].get('label','B')}={bv:.2f} exceeds limit "
                        f"{spec['a'].get('label','A')}={av:.2f}")
            continue

        tol = float(spec.get("tolerance", 0.1))
        denom = max(abs(av), abs(bv))
        drift = 0.0 if denom == 0 else abs(av - bv) / denom
        if drift > tol:
            ctx.add(sev, "corroboration", nm, "C1-source-disagreement",
                    f"{spec['a'].get('label','A')}={av:g} vs {spec['b'].get('label','B')}={bv:g} "
                    f"({drift:.0%} apart, tolerance {tol:.0%}). {spec.get('why','')[:180]}")


def check_links(ctx: Ctx, name: str, dash: dict, known_uids: set) -> None:
    """Internal drill-downs must point at a dashboard that exists.

    A /d/<uid> link to a UID outside the shipped set renders as a Grafana
    "Dashboard not found" only when someone clicks it, so it survives review
    indefinitely. known_uids is the set of UIDs across all files being
    validated together; a link outside that set is reported.
    """
    if not known_uids:
        return
    for p in iter_panels(dash):
        title = p.get("title") or f"(id {p.get('id')})"
        for link in (p.get("links") or []):
            m = LINK_UID_RE.search(link.get("url") or "")
            if m and m.group(1) not in known_uids:
                ctx.add(SEV_ERROR, name, title, "S5-dangling-link",
                        f"drill-down targets /d/{m.group(1)} which is not among the "
                        f"validated dashboards ({', '.join(sorted(known_uids))})")
    for link in (dash.get("links") or []):
        m = LINK_UID_RE.search(link.get("url") or "")
        if m and m.group(1) not in known_uids:
            ctx.add(SEV_ERROR, name, "(dashboard link)", "S5-dangling-link",
                    f"dashboard-level link targets /d/{m.group(1)}, not among the validated set")


def check_datasource_vars(ctx: Ctx, name: str, dash: dict) -> None:
    """A datasource variable with neither a regex nor a pinned value autobinds.

    Grafana picks the first datasource of the right type, ordered by name. With
    one Prometheus that is harmless; with several Postgres datasources it means
    a panel can silently query the wrong database and return plausible rows from
    the wrong place. That has happened in this repo before.
    """
    for v in (dash.get("templating", {}).get("list") or []):
        if v.get("type") != "datasource":
            continue
        pinned = bool((v.get("regex") or "").strip()) or bool((v.get("current") or {}).get("value"))
        if pinned:
            continue
        # Only ambiguous when more than one datasource of that type can exist.
        if (v.get("query") or "").lower() in AMBIGUOUS_DS_TYPES:
            ctx.add(SEV_ERROR, name, f"var:{v.get('name')}", "S6-unpinned-datasource",
                    f"datasource variable {v.get('name')} has no regex and no pinned value; "
                    f"Grafana will autobind to whichever '{v.get('query')}' datasource sorts first")


def check_promql_lint(ctx: Ctx, name: str, panel_title: str, expr: str,
                      dash_range_s: float | None, scalars: dict | None = None) -> None:
    # Range selectors may be driven by a dashboard variable (e.g. [$prom_retention]).
    # Resolve those first, otherwise the retention check silently skips the very
    # panels that were templated to make retention explicit.
    expr = subst_scalars(expr, scalars or {})
    # L1 rate()/increase() over a gauge
    for func, metric in FUNC_ON_METRIC_RE.findall(expr):
        mtype = ctx.meta.get(metric)
        if mtype == "gauge":
            ctx.add(SEV_ERROR, name, panel_title, "L1-gauge-rate",
                    f"{func}() applied to {metric}, which Prometheus reports as a GAUGE "
                    f"(the _total suffix is not a reliable signal)")

    # L2 window longer than retention
    if ctx.retention_s:
        for raw in RANGE_RE.findall(expr):
            if dur_to_s(raw) > ctx.retention_s * 1.05:
                ctx.add(SEV_ERROR, name, panel_title, "L2-window>retention",
                        f"[{raw}] exceeds Prometheus retention "
                        f"(~{ctx.retention_s/86400:.1f}d); result is silently computed "
                        f"over less data than the label implies")
        if "$__range" in expr and dash_range_s and dash_range_s > ctx.retention_s * 1.05:
            ctx.add(SEV_ERROR, name, panel_title, "L2-range>retention",
                    f"$__range with a default dashboard range of ~{dash_range_s/86400:.1f}d "
                    f"exceeds retention ~{ctx.retention_s/86400:.1f}d")

    # L3 count() over kube-state condition series
    for metric in KUBE_COND_COUNT_RE.findall(expr):
        ctx.add(SEV_ERROR, name, panel_title, "L3-count-condition",
                f"count() over {metric}: kube-state-metrics emits one series per condition "
                f"value permanently, so this counts SERIES not resources and cannot fall "
                f"when the condition flips. Use sum() of the status=\"true\" series.")

    # L4 metric existence
    if ctx.meta:
        for metric in set(METRIC_RE.findall(expr)):
            if metric in PROMQL_KEYWORDS or metric in SYNTHETIC_METRICS:
                continue
            if metric not in ctx.meta and not metric.startswith("__"):
                base = re.sub(r"_(bucket|count|sum)$", "", metric)
                if base not in ctx.meta:
                    ctx.add(SEV_WARN, name, panel_title, "L4-unknown-metric",
                            f"{metric} has no metadata in this Prometheus (may be absent)")


def scalar_vars(dash: dict) -> dict[str, str]:
    """Declared textbox/constant/custom variables and their current values.

    These are interpolated by Grafana as bare scalars anywhere in a query, not
    just inside label matchers, so they must be substituted before execution or
    the query is not even parseable.
    """
    out = {}
    for v in (dash.get("templating", {}).get("list") or []):
        if v.get("type") in ("textbox", "constant", "custom"):
            cur = (v.get("current") or {}).get("value")
            if isinstance(cur, str) and cur != "":
                out[v["name"]] = cur
    return out


def subst_scalars(q: str, scalars: dict[str, str]) -> str:
    for k, val in scalars.items():
        q = q.replace("${" + k + "}", val).replace("$" + k, val)
    return q


def _out_of_declared_range(panel: dict, v: float):
    """Return (min, max) when a value falls outside the panel's declared bounds.

    A panel that declares max: 1 and renders 1.14 is not a display quirk -- the
    query is wrong. Grafana clamps to the bound, so the tile looks reasonable
    while the underlying number is not. This caught a Cluster Status tile
    reading 114% because its denominator was a hardcoded target count that went
    stale when a new scrape target was added.
    """
    d = (panel or {}).get("fieldConfig", {}).get("defaults", {})
    lo, hi = d.get("min"), d.get("max")
    if hi is not None and v > float(hi) * 1.001:
        return (lo, hi)
    if lo is not None and v < float(lo) - abs(float(lo)) * 0.001 - 1e-9:
        return (lo, hi)
    return None


def run_promql(ctx: Ctx, name: str, title: str, expr: str, scalars: dict,
               panel: dict | None = None) -> None:
    q = expr
    q = q.replace("$__range", "1h").replace("$__rate_interval", "5m").replace("$__interval", "5m")
    q = subst_scalars(q, scalars)
    q = re.sub(r'=~\s*"\$namespace"', '=~"teleport"', q)
    q = re.sub(r'=~\s*"\$\w+"', '=~".+"', q)
    q = re.sub(r'=\s*"\$\w+"', '=~".+"', q)
    leftover = [v for v in VAR_RE.findall(q) if v not in GRAFANA_BUILTINS]
    if leftover:
        ctx.add(SEV_OK, name, title, "D0-skipped",
                f"not executed: unresolved dashboard variable(s) {sorted(set(leftover))}")
        return
    r = prom_get(ctx, "/api/v1/query", {"query": q})
    if r is None or r.get("status") != "success":
        ctx.add(SEV_ERROR, name, title, "D1-query-error",
                f"PromQL failed: {(r or {}).get('error', 'request failed')}")
        return
    res = (r.get("data") or {}).get("result") or []
    if not res:
        ctx.add(SEV_WARN, name, title, "D2-empty", "query returned no series")
        return
    for s in res[:1]:
        try:
            v = float(s["value"][1])
            if math.isnan(v):
                ctx.add(SEV_ERROR, name, title, "D3-NaN",
                        "result is NaN (typically 0/0) — renders as a threshold colour and misleads")
            elif _out_of_declared_range(panel, v) is not None:
                lo, hi = _out_of_declared_range(panel, v)
                ctx.add(SEV_ERROR, name, title, "D4-out-of-range",
                        f"result {v:g} falls outside the panel's own declared range "
                        f"[{lo}, {hi}]. Grafana clamps to the bound, so the tile renders a "
                        f"plausible value while the real number is wrong -- usually a ratio "
                        f"whose denominator has gone stale.")
            elif math.isinf(v):
                # Division by an unset dashboard variable is the common cause.
                # Grafana renders +Inf as a real-looking value, so it misleads
                # exactly like NaN does.
                ctx.add(SEV_ERROR, name, title, "D3-Inf",
                        f"result is {'+' if v > 0 else '-'}Inf (typically division by zero, often an "
                        f"unset dashboard variable) — Grafana renders it as a value")
        except (KeyError, ValueError):
            pass


def run_sql(ctx: Ctx, name: str, title: str, sql: str, ds_var: str | None) -> None:
    db = DB_FOR_DATASOURCE.get(ds_var or "", "teleport")
    q = sql
    tenant = get_tenant(ctx)
    if tenant:
        q = q.replace("${tenant}", tenant).replace("$tenant", tenant)
    q = re.sub(r"\$__timeFrom\(\)", "(now() - interval '90 days')", q)
    q = re.sub(r"\$__timeTo\(\)", "now()", q)
    q = re.sub(r"\$__timeFilter\(([^)]+)\)", r"\1 > now() - interval '90 days'", q)
    # Remaining ${var} placeholders are operator-supplied; skip rather than guess.
    leftover = [v for v in VAR_RE.findall(q) if v not in GRAFANA_BUILTINS]
    if leftover:
        ctx.add(SEV_OK, name, title, "D0-skipped",
                f"not executed: unresolved dashboard variable(s) {sorted(set(leftover))}")
        return
    rc, out = sh(["kubectl", "-n", PG_NS, "exec", "-i", PG_POD, "-c", PG_CONTAINER, "--",
                  "psql", "-U", "postgres", "-d", db, "-t", "-A", "-v", "ON_ERROR_STOP=1", "-f", "-"],
                 stdin=q if q.rstrip().endswith(";") else q + ";")
    if rc != 0:
        first = next((l for l in out.splitlines() if "ERROR" in l), out.strip().splitlines()[:1])
        ctx.add(SEV_ERROR, name, title, "D1-query-error", f"SQL failed [{db}]: {first}")
        return
    rows = [l for l in out.strip().splitlines() if l.strip() and not l.startswith("SET")]
    if not rows:
        ctx.add(SEV_WARN, name, title, "D2-empty", f"SQL returned no rows [{db}]")


# ---------------------------------------------------------------- driver

def validate(ctx: Ctx, path: str, known_uids: set | None = None) -> None:
    name = os.path.basename(path)
    try:
        dash = json.load(open(path))
    except Exception as e:
        ctx.add(SEV_ERROR, name, "-", "S1-parse", f"{e}")
        return

    check_structure(ctx, name, dash)
    check_links(ctx, name, dash, known_uids or set())
    check_datasource_vars(ctx, name, dash)

    dash_range_s = None
    frm = ((dash.get("time") or {}).get("from") or "")
    m = re.fullmatch(r"now-(\d+[smhdwy])", frm)
    if m:
        dash_range_s = dur_to_s(m.group(1))

    scalars = scalar_vars(dash)
    for p in iter_panels(dash):
        if p.get("type") == "row":
            continue
        title = p.get("title") or f"(id {p.get('id')})"
        # A per-panel timeFrom overrides the dashboard range for L2 purposes.
        panel_range_s = dur_to_s(p["timeFrom"]) if p.get("timeFrom") else dash_range_s
        for t in p.get("targets", []) or []:
            expr, sql = t.get("expr"), t.get("rawSql")
            if expr:
                check_promql_lint(ctx, name, title, expr, panel_range_s, scalars)
                if not ctx.offline:
                    run_promql(ctx, name, title, expr, scalars, p)
            elif sql and not ctx.offline:
                run_sql(ctx, name, title, subst_scalars(sql, scalars), ds_var_of(t) or ds_var_of(p))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="dashboard JSON (default: dashboards/*.json)")
    ap.add_argument("--prom", default=os.environ.get("PROM_URL", PROM_DEFAULT))
    ap.add_argument("--offline", action="store_true", help="structural + static lint only")
    ap.add_argument("--quiet", action="store_true", help="suppress OK/skip lines")
    ap.add_argument("--corroborate", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                          "corroborations.json"),
                    help="cross-source corroboration spec (C1). Set to '' to disable.")
    ap.add_argument("--uid-set", default="",
                    help="extra comma-separated dashboard UIDs that exist in the target "
                         "Grafana but are not in this directory (S5 link check)")
    a = ap.parse_args()

    files = a.files
    if not files:
        here = os.path.dirname(os.path.abspath(__file__))
        dd = os.path.join(here, "..", "dashboards")
        files = sorted(os.path.join(dd, f) for f in os.listdir(dd) if f.endswith(".json"))

    ctx = Ctx(prom=a.prom, offline=a.offline)
    if not a.offline:
        load_prom_context(ctx)
        if ctx.retention_s:
            note = ""
            if ctx.actual_s and ctx.actual_s < ctx.retention_s * 0.95:
                note = f" (configured longer, but only {ctx.actual_s/86400:.1f}d of data exists yet)"
            print(f"Prometheus usable history ~{ctx.retention_s/86400:.1f}d{note}; "
                  f"{len(ctx.meta)} metric names known\n")
        else:
            print(f"WARNING: could not reach Prometheus at {a.prom}. "
                  f"Retention and gauge checks are DISABLED — run with --offline "
                  f"or fix --prom to get full coverage.\n")

    # The UID set must cover every dashboard that WILL be deployed alongside
    # these, not just the files named on the command line. Validating one file
    # in isolation would otherwise report every link to a sibling as dangling.
    # Scan each input file's directory for siblings.
    known_uids = set()
    scan = set(files)
    for f in files:
        d = os.path.dirname(os.path.abspath(f))
        scan.update(os.path.join(d, n) for n in os.listdir(d) if n.endswith(".json"))
    for f in scan:
        try:
            known_uids.add(json.load(open(f)).get("uid"))
        except Exception:
            pass
    known_uids.discard(None)
    if a.uid_set:
        known_uids.update(u.strip() for u in a.uid_set.split(",") if u.strip())

    for f in files:
        validate(ctx, f, known_uids)

    # C1 cross-checks datasources against each other rather than inspecting any
    # panel, so it belongs to a full-set run. Running it when someone validates
    # one file -- the self-test fixture especially -- adds findings that have
    # nothing to do with the file under test and breaks that fixture's contract.
    if not a.offline and a.corroborate and not a.files:
        run_corroborations(ctx, a.corroborate)

    # If the transport itself was flaky, per-panel D1 findings are noise rather
    # than defects. Say so once, loudly, instead of reporting phantom failures.
    if ctx.prom_unreachable:
        print(f"\n!! Prometheus was unreachable for {ctx.prom_unreachable} request(s) after retries.\n"
              f"   Any D1-query-error below may be transport, not a real defect. Re-run before\n"
              f"   acting on them -- an intermittently wrong validator is worse than no validator.\n")

    order = {SEV_ERROR: 0, SEV_WARN: 1, SEV_OK: 2}
    findings = sorted(ctx.findings, key=lambda f: (order[f.severity], f.dashboard, f.panel))
    errors = sum(1 for f in findings if f.severity == SEV_ERROR)
    warns = sum(1 for f in findings if f.severity == SEV_WARN)

    cur = None
    for f in findings:
        if a.quiet and f.severity == SEV_OK:
            continue
        if f.dashboard != cur:
            cur = f.dashboard
            print(f"\n=== {cur} ===")
        print(f"  [{f.severity:5}] {f.check:22} {f.panel[:44]:44} {f.detail}")

    print(f"\n{len(files)} dashboard(s): {errors} error(s), {warns} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
