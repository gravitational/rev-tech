# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

Two standalone Go programs for investigative reporting against a Teleport cluster's audit log and resource APIs. Output is intended for capacity planning and ballpark billing checks — **not** an authoritative source for license counts (see disclaimer in `MAU_README.md` / `TPR_README.md`).

- `mau.go` — one-shot Monthly Active Users report (Zero Trust Access + Identity Governance) over the last N days of audit events, or aligned to billing cycles when `-billing-day` is set.
- `tpr.go` — long-lived service that polls Teleport for Protected Resources and Machine & Workload Identity counts, persists history to SQLite, and re-emits a report each interval. Optionally appends a per-billing-cycle history table.

Both share the same `package main` and the same `go.mod` (module name `teleport-mau`), but are compiled and run independently — there is no shared library code. Any helper used by both files is duplicated by hand (cycle math, preflight helpers, etc); keep them byte-identical so diffs are easy.

## How to build and run

End-user entrypoints are the two binaries published in [GitHub releases](https://github.com/gravitational/rev-tech/releases). Each release is tagged `teleport-api-scripts-v<teleport-version>` and contains tarballs/zips for linux/darwin/windows on amd64/arm64. Users grab the binary matching their cluster's Teleport version and run it directly:

```bash
./teleport-mau-tracker -proxy teleport.example.com:443
./teleport-tpr-tracker -proxy teleport.example.com:443 -billing-day 7 -cycles 6
```

The release pipeline lives at `.github/workflows/release-teleport-api-scripts.yml` (repo root). It runs daily, checks `gravitational/teleport` for new releases, and skips if a matching `teleport-api-scripts-vX.Y.Z` release already exists on this repo — so scheduled runs are idempotent.

For source builds use the `Makefile`:

```bash
make build                                  # build for the host platform against the currently-pinned API version
make build-for TELEPORT_VERSION=v18.5.1     # repin go.mod to a specific Teleport version, then build
GOOS=windows GOARCH=amd64 make build        # cross-compile (produces .exe automatically)
```

The Teleport API version in `go.mod` is intentionally floating — it gets bumped per release in the workflow and source builders can repin via `make build-for`. Don't read meaning into the current value on main.

Both binaries are pure Go (`CGO_ENABLED=0`). TPR's SQLite driver is `modernc.org/sqlite` (pure Go) — **do not** swap it back to `github.com/mattn/go-sqlite3` without a strong reason, since that re-introduces CGO and breaks the single-runner cross-compile.

## Architecture notes worth knowing before editing

**Preflight.** Both binaries call `preflightProxy(proxy)` (auto-appends `:443`, HTTPS-probes `/v1/webapi/find` for reachability) and `preflightTshProfile(proxy)` (only when no `-identity_file` is given — uses `api/profile` to verify the active tsh profile points at the same proxy and hasn't expired). The helpers are duplicated byte-for-byte between `mau.go` and `tpr.go`; keep them in sync. They replace the old shell-based `run.sh` checks.

**Authentication.** Both programs use `github.com/gravitational/teleport/api/client`. They fall back to the local `tsh` profile by default; pass `-identity_file` to use an exported identity instead. The preflight helper above is what produces the friendly "run: tsh login --proxy …" message when credentials are missing/expired.

**MAU (`mau.go`) data flow.** Pulls audit events in batches of `batchSize` (default 5000) via the events API, classifies each event into either a ZTA resource-access bucket (SSH / Kube / DB / App / Desktop) or an IG governance bucket (access requests, access lists, SAML IdP). A user can appear in both ZTA and IG totals — that's by design, not a double-count bug. `classifyUserKind` inspects the raw event's `user_kind` field to label bot vs. human in the text report; the field is sometimes a string ("bot"/"human"/"USER_KIND_BOT") and sometimes a numeric enum, and both shapes are handled.

**Billing cycles.** When `-billing-day N` (1–31) is set on either binary, events / SQL rows are bucketed into half-open cycles `[anchor @ 00:00 UTC, anchor-of-next-month @ 00:00 UTC)`. Anchor days that don't exist in a given month (e.g. 31 in Feb) clamp to the last day of that month. The cycle helpers (`cycleBounds`, `cycleStart`, `cycleContaining`, `lastNCycles`) are duplicated between `mau.go` and `tpr.go` for the same "no shared lib" reason as the preflight helpers.

**TPR (`tpr.go`) data flow.** Maintains in-memory maps (`resources`, `botInstances`) protected by `resourcesMutex`, persists rolling counts to `teleport_usage_data.db` (SQLite via modernc), and trims rows older than `dataRetentionDays`. Each `updateInterval` tick: re-lists all resource kinds from the API, watches for `instance.join` / `bot.join` events since the last tick, evicts stale entries, then writes a fresh `Teleport_Usage_Report.{txt,json}`. SPIFFE ID issuance is counted *per period* (not cumulative), so the value resets each interval. Per-cycle TPR figures use `MAX` over the snapshot rows within each cycle window (the value is "peak within cycle"); cycles with no recorded snapshots render as `n/a` rather than 0 to distinguish "no data" from "real zero".

**Config style.** Tunables live as `var (...)` blocks at the top of each file (e.g. `daysBack`, `batchSize`, `updateInterval`, `dataRetentionDays`). The READMEs instruct users to edit these directly rather than expose them as flags — current flags are `-proxy`, `-identity_file`, `-format`, `-billing-day`, `-cycles`. Keep that convention if adding new knobs unless the user specifically wants a flag.

**Minimum Teleport role** for each script is documented inline in the respective README — MAU needs `event` read; TPR additionally needs label-wildcard read on app/db/kube/node/windows_desktop.

## Output artifacts (gitignored, see `.gitignore`)

- `Teleport_Active_Users.{txt,json}` — MAU report.
- `Teleport_Usage_Report.{txt,json}` — TPR report (overwritten each interval).
- `teleport_usage_data.db` — TPR SQLite history.
- `teleport_tracker.log` — TPR runtime log.
- `teleport-{mau,tpr}-tracker*` — built binaries (with or without `.exe`).
- `teleport-api-scripts-*.tar.gz` / `*.zip` — release tarballs/zips.

These are produced by running the scripts/Makefile and shouldn't be committed.
