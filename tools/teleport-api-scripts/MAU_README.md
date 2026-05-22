# Teleport Monthly Active Users (MAU) Report Generator

This Go script connects to a Teleport cluster to analyze user activity and resource usage over a specified time period. It generates reports tracking both Zero Trust Access (ZTA MAU) and Identity Governance (IG MAU) usage patterns.

## Disclaimer

This is not an official method to obtain licensing counts for Teleport clusters, it is provided for investigative
purposes only. The only official method to get accurate MAU and TPR counts is to view reported usage via Teleport Cloud
cluster or license portal.

## What It Does

The script tracks two categories of Monthly Active Users:

### Zero Trust Access MAU (ZTA MAU)
Users actively accessing protected resources:
- **SSH** - Server access sessions
- **Kubernetes** - Kubectl requests and k8s sessions
- **Database** - Database connection sessions
- **Application** - Application access sessions
- **Desktop** - Windows desktop sessions

### Identity Governance MAU (IG MAU)
Users utilizing just-in-time access and governance features:
- **Access Requests Created** - Users creating access requests
- **Access Requests Reviewed** - Users reviewing/approving access requests
- **Access List Memberships** - Users receiving roles via access list membership
- **Access List Reviews** - Users reviewing access lists
- **SAML IdP Sessions** - Users authenticating via Teleport SAML IdP

**Important**: Users may appear in both ZTA MAU and IG MAU categories if they use both resource access and governance features.

## Prebuilt Binaries (Recommended)

If you don't want to build from source, prebuilt binaries are published as
GitHub Releases on the `gravitational/rev-tech` repository for each Teleport
version. Each release tag follows the pattern `teleport-api-scripts-vX.Y.Z`
and matches the corresponding Teleport server version.

Pick the release matching your Teleport cluster's version, then download the
archive for your platform. Each archive contains both `teleport-mau-tracker`
and `teleport-tpr-tracker` binaries plus a copy of these READMEs.

| Platform        | Archive                                                                   |
|-----------------|---------------------------------------------------------------------------|
| linux-amd64     | `teleport-api-scripts-<version>-linux-amd64.tar.gz`                       |
| linux-arm64     | `teleport-api-scripts-<version>-linux-arm64.tar.gz`                       |
| darwin-amd64    | `teleport-api-scripts-<version>-darwin-amd64.tar.gz`                      |
| darwin-arm64    | `teleport-api-scripts-<version>-darwin-arm64.tar.gz`                      |
| windows-amd64   | `teleport-api-scripts-<version>-windows-amd64.zip` (binaries end in `.exe`) |
| windows-arm64   | `teleport-api-scripts-<version>-windows-arm64.zip` (binaries end in `.exe`) |

```bash
# Example: grab the binary matching your cluster's Teleport version (Linux/macOS)
TELEPORT_VERSION=v18.5.1   # check via: curl -s https://<proxy>/v1/webapi/find | jq -r .server_version
gh release download teleport-api-scripts-${TELEPORT_VERSION} \
  --repo gravitational/rev-tech \
  --pattern '*linux-amd64*.tar.gz'
tar xzf teleport-api-scripts-${TELEPORT_VERSION}-linux-amd64.tar.gz
cd teleport-api-scripts-${TELEPORT_VERSION}-linux-amd64
./teleport-mau-tracker -proxy <your-proxy>:443
```

```powershell
# Windows (PowerShell)
$TELEPORT_VERSION = "v18.5.1"
gh release download "teleport-api-scripts-$TELEPORT_VERSION" `
  --repo gravitational/rev-tech `
  --pattern "*windows-amd64*.zip"
Expand-Archive "teleport-api-scripts-$TELEPORT_VERSION-windows-amd64.zip"
cd "teleport-api-scripts-$TELEPORT_VERSION-windows-amd64\teleport-api-scripts-$TELEPORT_VERSION-windows-amd64"
.\teleport-mau-tracker.exe -proxy <your-proxy>:443
```

## Prerequisites (when building from source)

- Go 1.24+ installed
- Access to a Teleport cluster with audit log read permissions
- Valid Teleport credentials (see [Authentication](#authentication) section below)
- Network connectivity to your Teleport proxy and to github.com/golang.org repositories

## Installation (source build)

```bash
git clone https://github.com/gravitational/rev-tech.git
cd rev-tech/tools/teleport-api-scripts
make build           # builds against the currently-pinned Teleport API version
```

To re-pin the API to a specific Teleport version before building:

```bash
make build-for TELEPORT_VERSION=v18.5.1
```

That runs `go get github.com/gravitational/teleport/api@v18.5.1`, `go mod tidy`, and `make build`. Cross-compile for other platforms by setting `GOOS`/`GOARCH`:

```bash
GOOS=linux GOARCH=amd64 make build
GOOS=windows GOARCH=amd64 make build   # produces teleport-mau-tracker.exe
```

## Customization

### Common Customizations

Customizations are made by modifying the configuration variables at the top of the script:

**Change time range:**
```go
daysBack = 60  // Default is 30 days back
```

**Optimize for large clusters:**
```go
batchSize = 10000  // Increase batch size for better performance. Default is 5000
```

## Billing Cycles

Teleport bills against monthly cycles anchored to a customer-specific day, not the
1st of each month. To produce a report that lines up with the "Usage History" view
in Teleport Cloud, pass `-billing-day` with your anchor day (1-31):

```bash
# Aligned to cycles starting on the 7th of each month (e.g. 7 May - 6 Jun)
./teleport-mau-tracker -proxy teleport.example.com:443 -billing-day 7

# Include 5 completed cycles in addition to the in-progress one (default: 3)
./teleport-mau-tracker -proxy teleport.example.com:443 -billing-day 7 -cycles 5
```

When `-billing-day` is set:
- The report contains one row per cycle (oldest → newest, with the in-progress
  cycle last), matching the schema of the Teleport portal's Usage History page.
- Each cycle has its own detailed per-user ZTA/IG breakdown underneath.
- Anchor days that exceed a given month's length (e.g. 31 in February) are
  clamped to the last day of that month.
- All cycle math is in UTC. The script uses the audit log's `time` field to
  bucket each event into a cycle.

Without `-billing-day` (default), the script keeps its original rolling-window
behavior driven by `daysBack` in the source.

Caveat: events older than your cluster's audit log retention will not be
returned, so older cycles may be silently empty. A warning is logged if the
requested window exceeds ~90 days.

## Authentication

The script automatically handles authentication based on your configuration:

### Option 1: User Profile (Default)
Uses your current `tsh` login session - no additional setup required.

**Note**: This method will eventually fail when your credentials expire unless refreshed.

If you have multiple sets of `tsh` credentials locally, you must make sure that `tctl status` outputs
the correct cluster name before running the script. You can use `tsh login --proxy teleport.example.com:443` to
"switch" active credentials.

### Option 2: Identity File (Recommended for remote runs or automation)
For continuous/automated jobs:

1. Generate an identity file:
   ```bash
  tsh login --proxy=teleport.example.com:443 --auth=your_auth_method --out=identity-file
   ```

(for an alternative, use [Machine ID](https://goteleport.com/docs/machine-workload-identity/access-guides/tctl/))

2. Provide the identity file to the binary:
   ```bash
   ./teleport-mau-tracker -proxy teleport.example.com:443 -identity_file /path/to/your/identity-file
   ```

(for Machine ID, you want the `identity` file in the bot's output directory)

The binary uses the identity file when `-identity_file` is provided; otherwise it falls back to the active `tsh` profile.

## Running

```bash
# port 443 is assumed if you provide no port
./teleport-mau-tracker -proxy teleport.example.com:443

# Output as JSON instead of text
./teleport-mau-tracker -proxy teleport.example.com:443 -format json

# Align reports to billing cycles starting on the 7th of each month, with 3 completed cycles of history
./teleport-mau-tracker -proxy teleport.example.com:443 -billing-day 7 -cycles 3
```

Before connecting, the binary performs a couple of preflight checks: it probes
`https://<proxy>/v1/webapi/find` for reachability, and (when no `-identity_file`
is given) verifies that the active `tsh` profile points at the same proxy and
hasn't expired. Failures produce a clear message with the exact `tsh login`
command to run.

### Running mau and tpr together

`teleport-mau-tracker` is one-shot; `teleport-tpr-tracker` is a long-lived
service. If you want both, run them separately — typically the TPR tracker in
the background (or under systemd/Docker) and the MAU tracker on demand or via
cron:

```bash
# In one terminal (or backgrounded / as a service)
./teleport-tpr-tracker -proxy teleport.example.com:443

# In another terminal whenever you want a fresh MAU snapshot
./teleport-mau-tracker -proxy teleport.example.com:443
```

## Output

### JSON Format (`-format json`)
Creates `Teleport_Active_Users.json` with:
```json
{
  "timestamp": "2025-09-05 11:02:21",
  "teleport_proxy_url": "teleport.example.com:443",
  "total_ztamau": 2,
  "total_igmau": 1,
  "total_successful_logins": 93,
  "zta_resource_usage": {
    "user@example.com": {
      "login_count": 27,
      "ssh": 14,
      "kubernetes": 5,
      "database": 0,
      "application": 0,
      "desktop": 25
    }
  },
  "ig_feature_usage": {
    "admin@example.com": {
      "access_requests_created": 5,
      "access_requests_reviewed": 12,
      "access_lists_memberships": 2,
      "access_lists_reviewed": 3,
      "saml_idp_sessions": 0
    }
  }
}
```

### Text Format (`-format text`)
Creates `Teleport_Active_Users.txt` with formatted tables:
```
[2025-12-17 16:52:15] Teleport Active Users Report
Teleport Proxy URL: teleport.example.com:443
=================================================
Total Zero Trust Access MAU (ZTA MAU): 2
Total Identity Governance MAU (IG MAU): 2
Total Machine and Workload Identity Bot users (MWI): 1
Total Successful Logins: 38
=================================================

ZERO TRUST ACCESS (ZTA MAU) - Resource Usage
-------------------------------------------------
User                                Kind    Logins    SSH       Kube      DB        App       Desktop
--------------------------------------------------------------------------------------------------------
bot-gus-teleportdemo-com-app-bot    Bot     0         0         0         0         2163      0
user@goteleport.com                 Human   29        8         0         0         1         0

IDENTITY GOVERNANCE (IG MAU) - Feature Usage
-------------------------------------------------
User                     Req Created   Req Reviewed  List Member   List Review   SAML IdP
-----------------------------------------------------------------------------------------------
user@goteleport.com      0             0             0             0             1
```

## Understanding the Results

### Zero Trust Access MAU (ZTAMAU)
- **Total ZTA MAU**: Users who actively accessed at least one protected resource
- **Total Successful Logins**: All successful login events in the time period
- **Per-User Resource Breakdown**:
  - **Logins**: Number of successful authentication events
  - **SSH**: Server access sessions initiated
  - **Kube**: Kubernetes requests and sessions
  - **DB**: Database connection sessions
  - **App**: Application access sessions
  - **Desktop**: Windows desktop sessions

### Identity Governance MAU (IGMAU)
- **Total IG MAU**: Users who utilized at least one identity governance feature
- **Per-User Feature Breakdown**:
  - **Req Created**: Access requests created by the user
  - **Req Reviewed**: Access requests reviewed/approved by the user
  - **List Member**: Times user received roles via access list membership
  - **List Review**: Access lists reviewed by the user
  - **SAML IdP**: SAML IdP authentication sessions initiated

**Note**: A single user may appear in both ZTA MAU and IG MAU if they both access resources and use governance features.

## Troubleshooting

### Common Issues

1. **Connection Failed**: Verify your proxy URL and network connectivity
2. **Authentication Failed**: Check your `tsh` login status or identity file path, your credentials must be the currently active set
3. **No Events Found**: Verify the time range and that users have been active
4. **Permission Denied**: Ensure your Teleport user has audit log read permissions

Here is a basic example of a role which has the minimum needed permissions to read audit events:

```yaml
kind: role
metadata:
  name: event-read-role
spec:
  allow:
    rules:
    - resources:
      - event
      verbs:
      - list
      - read
version: v7
```

### Performance Considerations

- Large clusters may take several minutes to process
- Increase batch size for better performance on busy clusters
- Consider shorter time ranges for initial testing

## Security Notes

- Identity files contain sensitive credentials - store them securely
- Limit script access to users who need audit log visibility
- Consider using Teleport RBAC to restrict audit access if needed

### Command-line flags

```
Usage: teleport-mau-tracker -proxy <teleport-proxy-address> [flags]

  -proxy           Teleport proxy address (required). :443 assumed if no port.
  -identity_file   Optional identity file path. Falls back to active tsh profile.
  -format          Output format: "text" (default) or "json".
  -billing-day     Billing cycle anchor day (1-31). Aligns reports with Teleport billing cycles.
  -cycles          Number of completed cycles to include (default 3, requires -billing-day).

Examples:
  teleport-mau-tracker -proxy example.teleport.sh
  teleport-mau-tracker -proxy example.teleport.sh:443 -identity_file /path/to/identity
  teleport-mau-tracker -proxy example.teleport.sh -billing-day 7 -cycles 3
```