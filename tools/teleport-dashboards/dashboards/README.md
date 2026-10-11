# Dashboard sources

The **source** set. Do not install these directly — render them first.

```bash
make render PROFILE=oss-postgres
```

`scripts/render-dashboards.py` drops panels whose capabilities the target cluster lacks, repacks the
layout, strips drill-downs to dashboards the profile skipped, and injects retention defaults.
Installing the raw JSON puts panels on screen whose datasource does not exist, and a panel reading
`0` because its datasource is missing is indistinguishable from a real measurement of zero.

| File | Dashboard | Reasoning |
|---|---|---|
| `teleport-executive.json` | Executive Summary | [teleport-executive.md](teleport-executive.md) |
| `teleport-identity-security.json` | Identity Security | [teleport-identity-security.md](teleport-identity-security.md) |
| `teleport-ops-health.json` | Ops Health | [teleport-ops-health.md](teleport-ops-health.md) |
| `teleport-identity.json` | Identity & Access | [teleport-identity.md](teleport-identity.md) |
| `teleport-overview.json` | Overview (TV) | [teleport-overview.md](teleport-overview.md) |

Each `.md` explains that dashboard panel by panel: what it answers, where the number comes from, and
why it is built the way it is rather than the obvious simpler way that would be wrong.

## Editing

- Every panel carries `x-requires`, naming the capabilities it needs. Grafana ignores unknown panel
  keys, so it is inert at runtime; the renderer filters on it. **A new panel without it inherits
  nothing and will ship into profiles that cannot run it.**
- Panel `description` fields carry the reasoning and caveats, and are the primary source for the
  per-dashboard READMEs. Keep them current.
- Dashboard UIDs are a contract — drill-downs reference `/d/<uid>/…` directly.
- Run `make validate` before committing. It executes every query and self-tests the validator.
