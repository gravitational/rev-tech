# Tooling

| Script | Purpose |
|---|---|
| `render-dashboards.py` | Filter dashboards to a capability profile, repack layout, inject retention defaults |
| `validate-dashboards.py` | Execute every panel query against a live cluster and fail on the ways these dashboards have actually been wrong |
| `test_render_dashboards.py` | Unit tests for the renderer |
| `corroborations.json` | Cross-source checks (`C1`) — two independent sources measuring the same quantity must agree |
| `testdata/dashboard-selftest.json` | One deliberately broken panel per check |

Stdlib-only Python 3, so both scripts run anywhere without a virtualenv.

## Why a validator exists

Reviewing dashboard JSON does not catch the failures that matter. Every defect found in this set ran
clean, returned a plausible value, and measured the wrong thing — a security board showing a green
`0` while 22 high-severity alerts were open, a "Worker Nodes Ready" tile that counted metric series
and could never decrease, a "Failed Logins" panel structurally incapable of observing a failed login.

```bash
make validate                      # offline: Go tests, renderer tests, self-test, every profile
make validate-live                 # executes every query against a live cluster
```

Point it at a different cluster:

```bash
TELEPORT_PG_NAMESPACE=teleport TELEPORT_PG_POD=my-pg-1 \
PROM_URL=http://localhost:9090 ./scripts/validate-dashboards.py
```

## The self-test

`dashboard-selftest.json` carries one planted bug per check and **must report exactly 8 errors**. A
check that silently stops firing is worse than no check — that happened here once, when the
NaN-detection fixture stopped detecting NaN the moment somebody logged in and `0/0` became `1`.
Fixtures must be deterministic and independent of live cluster state.

**Adding a check means adding a fixture case for it.** The `S6-unpinned-datasource` check shipped
without one and nothing would have caught it regressing.
