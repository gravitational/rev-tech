# get-client-versions

Extracts `tsh` client version information from a Teleport cluster's audit log by
querying `cert.create` and `user.login` events over a configurable time window.

Raw events are written to stdout. Progress and the per-user summary are written
to stderr, so you can redirect stdout to a file without losing the summary.

## How it works

When `tsh login` is run, Teleport records the tsh version in the `user_agent`
field of the resulting audit events (e.g. `tsh/18.6.4 grpc-go/1.75.0`). Silent
certificate renewals — where tsh refreshes credentials in the background — do
not include the tsh version, only the raw `grpc-go/x.y.z` string.

This tool filters to events that include a `tsh/` user agent, skipping:

- Events with no user agent set
- Bot-issued certificates (where `bot_name`, `bot_instance_id`, or a `bot-`
  username prefix is present)

After printing all matching events, it prints a summary table showing the most
recent tsh version seen per user.

## Requirements

- Go 1.21+
- An active `tsh` session with a role that has `read` and `list` permissions on
  the `event` resource

The following Teleport role grants the minimum permissions required:

```yaml
kind: role
version: v7
metadata:
  name: audit-log-reader
spec:
  allow:
    rules:
      - resources:
          - event
        verbs:
          - read
          - list
  deny: {}
```

Apply it with `tctl create -f role.yaml`, then assign it to your user with
`tctl users update <username> --set-roles <existing-roles>,audit-log-reader`.

## Installation

```bash
git clone <this repo>
cd tools/get-client-versions
go mod tidy
```

### Matching the Teleport API version to your cluster

The `github.com/gravitational/teleport/api` module must match your cluster's
Teleport version. Find your cluster version with:

```bash
tctl version
```

Then update the dependency using the exact commit for that release tag:

```bash
go get github.com/gravitational/teleport/api@$(git ls-remote https://github.com/gravitational/teleport "refs/tags/v18.6.4" | awk '{print $1}')
```

Replace `18.6.4` with your cluster version. Run `go mod tidy` afterwards.

## Usage

```
go run main.go --proxy <host:port> [--days <n>] [--verbose]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--proxy` | *(required)* | Teleport proxy address, e.g. `teleport.example.com:443` |
| `--days` | `90` | Number of days to look back in the audit log |
| `--verbose` | `false` | Print each matching event to stdout as it is found |

### Examples

Search the last 90 days:

```bash
go run main.go --proxy teleport.example.com:443
```

Search the last 30 days and save the event log to a file:

```bash
go run main.go --proxy teleport.example.com:443 --days 30 --verbose > events.txt
```

## Output

By default, only the per-user summary is printed to stdout. Pass `--verbose` to
also print each matching event as it is found.

Progress is printed to stderr while scanning, including the date of the most
recently seen event so you can gauge how far through the time window the scan
has progressed:

```
Searching audit events from 2025-12-05 to 2026-03-05...
  page 1     scanned 500    matched 12      latest event date 2025-12-09
  page 2     scanned 1000   matched 24      latest event date 2025-12-18
  ...
Done.
```

In verbose mode, matching events are printed to stdout as they are found:

```
event=cert.create     time=2026-02-10T17:49:23Z  user=alice  user_agent=tsh/18.6.6 grpc-go/1.75.0
```

The per-user summary is always printed to stdout at the end:

```
--- Latest tsh version per user ---
  alice                           tsh/18.6.6            last seen 2026-02-13T15:44:03Z  via cert.create
  bob                             tsh/18.5.0            last seen 2026-01-15T09:22:11Z  via cert.create
```