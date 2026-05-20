# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

Two standalone Go programs for investigative reporting against a Teleport cluster's audit log and resource APIs. Output is intended for capacity planning and ballpark billing checks — **not** an authoritative source for license counts (see disclaimer in `MAU_README.md` / `TPR_README.md`).

- `mau.go` — one-shot Monthly Active Users report (Zero Trust Access + Identity Governance) over the last N days of audit events.
- `tpr.go` — long-lived service that polls Teleport for Protected Resources and Machine & Workload Identity counts, persists history to SQLite, and re-emits a report each interval.

Both share the same `package main` and the same `go.mod` (module name `teleport-mau`), but are compiled and run independently — there is no shared library code. They are co-located only because they share the `run.sh` launcher.

## How to build and run

The expected entrypoint for end users is `run.sh`, which:
1. Probes `https://<proxy>/v1/webapi/find` for `server_version`.
2. Resolves that tag to a commit SHA on `github.com/gravitational/teleport` and runs `go get github.com/gravitational/teleport/api@<sha>` + `go mod tidy` so the API client version matches the cluster.
3. Runs `go run mau.go` and/or `go run tpr.go` against the proxy.

This means **the version pin in `go.mod` for `github.com/gravitational/teleport/api` is expected to drift** depending on which cluster was last targeted — don't treat changes to that pin as meaningful unless you're updating it deliberately.

Common invocations:

```bash
# MAU report (uses current tsh login)
bash ./run.sh -p teleport.example.com:443 -m

# TPR tracker with identity file (recommended for long-running)
bash ./run.sh -p teleport.example.com:443 -i /path/to/identity -t

# Build standalone binaries (TPR needs CGO for sqlite)
go build -o teleport-mau-tracker mau.go
CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o teleport-tpr-tracker tpr.go
```

`run.sh` requires `curl`, `go`, `git`, `jq`, `tsh` on PATH. There is no test suite and no linter wired up.

## Architecture notes worth knowing before editing

**Authentication.** Both programs use `github.com/gravitational/teleport/api/client`. They fall back to the local `tsh` profile by default; pass `-identity_file` to use an exported identity instead. `run.sh` validates the tsh profile's `valid_until` before launching and refuses to run with an expired profile.

**MAU (`mau.go`) data flow.** Pulls audit events in batches of `batchSize` (default 5000) via the events API, classifies each event into either a ZTA resource-access bucket (SSH / Kube / DB / App / Desktop) or an IG governance bucket (access requests, access lists, SAML IdP). A user can appear in both ZTA and IG totals — that's by design, not a double-count bug. `classifyUserKind` inspects the raw event's `user_kind` field to label bot vs. human in the text report; the field is sometimes a string ("bot"/"human"/"USER_KIND_BOT") and sometimes a numeric enum, and both shapes are handled.

**TPR (`tpr.go`) data flow.** Maintains in-memory maps (`resources`, `botInstances`) protected by `resourcesMutex`, persists rolling counts to `teleport_usage_data.db` (SQLite, hence the CGO requirement), and trims rows older than `dataRetentionDays`. Each `updateInterval` tick: re-lists all resource kinds from the API, watches for `instance.join` / `bot.join` events since the last tick, evicts stale entries, then writes a fresh `Teleport_Usage_Report.{txt,json}`. SPIFFE ID issuance is counted *per period* (not cumulative), so the value resets each interval.

**Config style.** Tunables live as `var (...)` blocks at the top of each file (e.g. `daysBack`, `batchSize`, `updateInterval`, `dataRetentionDays`). The READMEs instruct users to edit these directly rather than expose them as flags — only `-proxy`, `-identity_file`, and `-format` are flags. Keep that convention if adding new knobs unless the user specifically wants a flag.

**Minimum Teleport role** for each script is documented inline in the respective README — MAU needs `event` read; TPR additionally needs label-wildcard read on app/db/kube/node/windows_desktop.

## Output artifacts (gitignored in practice, present in working tree)

- `Teleport_Active_Users.{txt,json}` — MAU report.
- `Teleport_Usage_Report.{txt,json}` — TPR report (overwritten each interval).
- `teleport_usage_data.db` — TPR SQLite history.
- `teleport_tracker.log` — TPR runtime log.
- `teleport-{mau,tpr}-tracker-*` — built binaries.

These are produced by running the scripts and shouldn't be committed.
