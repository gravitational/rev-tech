#!/usr/bin/env python3
"""
render-dashboards.py — produce dashboards for a specific deployment.

Panels declare what they need via `x-requires`. This filters a dashboard to a
capability profile, repacks the layout so removed panels leave no holes, and
injects retention defaults. The result is plain Grafana JSON with no templating
of any kind, so it can be delivered by a ConfigMap, Grafana's HTTP API, file
provisioning, Terraform, or Grizzly.

Panels are OMITTED rather than left to render "No data". An empty panel on a
dashboard someone makes decisions from is worse than an absent one: it looks
like a measurement of zero.

Usage:
  ./render-dashboards.py --profile profiles/oss-postgres.yaml --out rendered/oss-postgres
  ./render-dashboards.py --profile profiles/oss-postgres.yaml --out rendered/oss --in dashboards
"""
from __future__ import annotations
import argparse, json, os, re, sys

GRID_W = 24


def parse_profile(path: str) -> tuple[set[str], dict, str]:
    """Minimal YAML reader for the profile shape this project uses.

    Deliberately not PyYAML: the renderer must run anywhere with stdlib only.
    Supports exactly `name:`, `capabilities:` (a `- item` list) and
    `variables:` (a flat `key: value` map).
    """
    caps: set[str] = set()
    variables: dict[str, str] = {}
    name = os.path.splitext(os.path.basename(path))[0]
    section = None
    for raw in open(path):
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if not line.startswith((" ", "\t", "-")):
            key = line.split(":", 1)[0].strip()
            section = key
            if key == "name":
                val = line.split(":", 1)[1].strip()
                if val:
                    name = val.strip("'\"")
            continue
        item = line.strip()
        if section == "capabilities" and item.startswith("- "):
            caps.add(item[2:].strip().strip("'\""))
        elif section == "variables" and ":" in item:
            k, v = item.split(":", 1)
            variables[k.strip()] = v.strip().strip("'\"")
    return caps, variables, name


def has_data_panels(dash: dict) -> bool:
    """True if anything remains that actually queries something.

    Rows are structure and text panels are prose. A dashboard reduced to those
    is worse than an absent one: it appears in the Grafana nav looking like a
    broken install rather than an unsupported one.
    """
    for p in dash.get("panels", []):
        if p.get("type") not in ("row", "text"):
            return True
        for sp in p.get("panels", []) or []:
            if sp.get("type") not in ("row", "text"):
                return True
    return False


def _filter_panels(panels: list, caps: set[str], dropped: list) -> list:
    keep = []
    for p in panels:
        if p.get("type") == "row":
            # Collapsed rows carry their children here rather than at top level,
            # so they must be filtered too or unsupported panels survive inside.
            if p.get("panels"):
                p["panels"] = _filter_panels(p["panels"], caps, dropped)
            keep.append(p)
            continue
        req = p.get("x-requires") or []
        if all(c in caps for c in req):
            keep.append(p)
        else:
            dropped.append((p.get("title", "?"), [c for c in req if c not in caps]))
    return keep


def render(dash: dict, caps: set[str], variables: dict) -> dict:
    dropped: list = []
    kept = _filter_panels(dash.get("panels", []), caps, dropped)

    kept = _drop_empty_rows(kept)
    dash["panels"] = _repack(kept)

    for v in dash.get("templating", {}).get("list", []):
        if v.get("name") in variables:
            val = variables[v["name"]]
            v["current"] = {"text": val, "value": val}
            v["query"] = val
            if v.get("options"):
                v["options"] = [{"selected": True, "text": val, "value": val}]

    if dropped:
        names = ", ".join(f"{t} (needs {'+'.join(m)})" for t, m in dropped)
        note = (f"\n\n---\n\n**{len(dropped)} panel(s) omitted for this deployment:** {names}. "
                f"Panels are omitted rather than shown empty — a panel reading zero because its "
                f"datasource is absent is indistinguishable from a real measurement of zero.")
        dash["description"] = (dash.get("description", "") + note).strip()
    return dash


def _drop_empty_rows(panels: list) -> list:
    """Remove a row header that has no content panels before the next row."""
    out = []
    for i, p in enumerate(panels):
        if p.get("type") != "row":
            out.append(p)
            continue
        # A collapsed row holds its children inline; an expanded row is followed
        # by its children at top level until the next row.
        has_content = bool(p.get("panels"))
        for nxt in panels[i + 1:]:
            if nxt.get("type") == "row":
                break
            has_content = True
            break
        if has_content:
            out.append(p)
    return out


def _repack(panels: list) -> list:
    """Reflow panels so removals leave no holes.

    Within each row segment, lay panels out left-to-right at their original
    widths, wrapping at 24 columns. Row headers always start a new band. Without
    this, deleting a panel leaves a gap that Grafana renders as dead space.
    """
    y = 0
    x = 0
    band_h = 0
    for p in panels:
        g = p.setdefault("gridPos", {})
        w = min(int(g.get("w", GRID_W)), GRID_W)
        h = int(g.get("h", 6))
        if p.get("type") == "row":
            if x:
                y += band_h
                x, band_h = 0, 0
            g.update({"x": 0, "y": y, "w": GRID_W, "h": 1})
            y += 1
            continue
        if x + w > GRID_W:
            y += band_h
            x, band_h = 0, 0
        g.update({"x": x, "y": y, "w": w, "h": h})
        x += w
        band_h = max(band_h, h)
    return panels


def strip_dangling_links(dash: dict, present_uids: set) -> int:
    """Remove drill-downs to dashboards this profile does not ship.

    A panel that survives capability filtering can still link to a dashboard
    that was skipped. Grafana renders that as "Dashboard not found" only on
    click, so it would ship silently. Today the executive board's links happen
    to sit on Access-Graph panels that get dropped alongside their target, but
    that is a coincidence of layout, not a guarantee.
    """
    removed = 0
    for p in list(dash.get("panels", [])) :
        targets = [p] + list(p.get("panels") or [])
        for t in targets:
            links = t.get("links")
            if not links:
                continue
            keep = []
            for l in links:
                m = re.search(r"/d/([A-Za-z0-9_-]+)", l.get("url") or "")
                if m and m.group(1) not in present_uids:
                    removed += 1
                else:
                    keep.append(l)
            if keep:
                t["links"] = keep
            else:
                t.pop("links", None)
    return removed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True)
    ap.add_argument("--in", dest="indir", default="dashboards")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    caps, variables, pname = parse_profile(a.profile)
    os.makedirs(a.out, exist_ok=True)
    print(f"profile {pname}: capabilities={sorted(caps)} variables={variables}")

    # Pass 1: filter each dashboard and note which ones survive.
    surviving = {}
    for fn in sorted(os.listdir(a.indir)):
        if not fn.endswith(".json"):
            continue
        dash = json.load(open(os.path.join(a.indir, fn)))
        total = sum(1 for p in dash.get("panels", []) if p.get("type") != "row")
        out = render(dash, caps, variables)
        if not has_data_panels(out):
            print(f"  {fn}: SKIPPED (0 of {total} data panels supported)")
            continue
        surviving[fn] = (out, total)

    # Pass 2: only now is it known which UIDs this profile actually ships, so
    # drill-downs to skipped dashboards can be removed.
    present = {d.get("uid") for d, _ in surviving.values()}
    present.discard(None)
    for fn, (out, total) in surviving.items():
        n = strip_dangling_links(out, present)
        kept = sum(1 for p in out.get("panels", []) if p.get("type") != "row")
        json.dump(out, open(os.path.join(a.out, fn), "w"), indent=2)
        extra = f", {n} dangling link(s) stripped" if n else ""
        print(f"  {fn}: {kept}/{total} panels{extra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
