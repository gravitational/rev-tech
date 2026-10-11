# teleport-usage

A single Go binary that unifies the two rev-tech Teleport usage trackers as
subcommands over shared internal packages. Output is for capacity planning and
ballpark billing checks — **not** an authoritative source for license counts.

## Subcommands

```bash
teleport-usage mau -proxy teleport.example.com:443
teleport-usage tpr -proxy teleport.example.com:443 -billing-day 7 -cycles 6
```

- `mau` — one-shot Monthly Active Users report (Zero Trust Access + Identity
  Governance) over the last N days of audit events, or aligned to billing
  cycles when `-billing-day` is set. Writes `Teleport_Active_Users.{txt,json}`.
- `tpr` — long-lived tracker that polls Teleport for Protected Resources and
  Machine & Workload Identity counts, persists rolling history to SQLite
  (`teleport_usage_data.db`), and re-emits `Teleport_Usage_Report.{txt,json}`
  each interval.

### Flags

Both subcommands share `-proxy`, `-identity_file`, `-format` (`text`|`json`),
`-billing-day` (1–31, `0` disables), and `-cycles`. The `tpr` subcommand adds:

- `-postgres-dsn` — optional Postgres DSN. When set, each snapshot row is also
  written to `public.tpr_history` / `public.mwi_history` alongside the SQLite
  store (used by the in-cluster Grafana usage dashboard). Empty (default) means
  SQLite only.

## Legacy aliases

The original release binaries were named `teleport-mau-tracker` and
`teleport-tpr-tracker`. The combined binary inspects `argv[0]`: invoking it via
a symlink whose name contains `mau` or `tpr` selects that subcommand directly,
so existing invocations keep working unchanged.

```bash
ln -sf teleport-usage teleport-mau-tracker
./teleport-mau-tracker -proxy teleport.example.com:443   # == teleport-usage mau ...
```

## Build

```bash
make build         # ./teleport-usage for the host platform (CGO_ENABLED=0)
make links         # build + create the legacy-name symlinks
make test          # go test ./...
make vet           # go vet ./...
make linux-amd64   # static linux/amd64 binary for the cluster nodes
```

Pure Go (`CGO_ENABLED=0`): the SQLite driver is `modernc.org/sqlite` and the
Postgres driver is `github.com/jackc/pgx/v5/stdlib`, so the binary
cross-compiles and links statically. `make build-for TELEPORT_VERSION=v18.5.1`
repins the Teleport API version before building.
