# Teleport Protected Resources (TPR) Report Generator

This Go script continuously monitors and tracks Teleport Protected Resources (TPRs) in your cluster. It provides real-time visibility into resource counts across all Teleport service types and maintains historical data for billing and capacity planning purposes.

## Disclaimer

This is not an official method to obtain licensing counts for Teleport clusters, it is provided for investigative
purposes only. The only official method to get accurate MAU and TPR counts is to view reported usage via Teleport Cloud
cluster or license portal.

## What It Does

The script tracks the following types of Teleport Protected Resources:
- **Applications** - Application servers registered with Teleport
- **Kubernetes Clusters** - Kubernetes clusters accessible through Teleport
- **Databases** - Database servers registered with Teleport
- **Windows Desktops** - Windows desktop resources
- **SSH Nodes** - SSH-accessible servers and instances
- **Bots** - Machine ID bots and their instances

**Key Features:**
- **Continuous Monitoring** - Runs as a long-lived service with configurable update intervals
- **Historical Tracking** - Stores TPR counts in SQLite database with configurable retention
- **Event Monitoring** - Watches for `instance.join` and `bot.join` events to detect new resources
- **Automated Reports** - Generates periodic reports in JSON or text format
- **Resource Cleanup** - Automatically removes stale resources from memory

## Prebuilt Binaries (Recommended)

If you don't want to build from source, prebuilt binaries are published as
GitHub Releases on the `gravitational/rev-tech` repository for each Teleport
version. Each release tag follows the pattern `teleport-api-scripts-vX.Y.Z`
and matches the corresponding Teleport server version.

Pick the release matching your Teleport cluster's version, then download the
tarball for your platform (linux-amd64, linux-arm64, darwin-amd64,
darwin-arm64). The tarball contains both `teleport-mau-tracker` and
`teleport-tpr-tracker` binaries plus a copy of these READMEs.

```bash
# Example: grab the binary matching your cluster's Teleport version
TELEPORT_VERSION=v18.5.1   # check via: curl -s https://<proxy>/v1/webapi/find | jq -r .server_version
gh release download teleport-api-scripts-${TELEPORT_VERSION} \
  --repo gravitational/rev-tech \
  --pattern '*linux-amd64*.tar.gz'
tar xzf teleport-api-scripts-${TELEPORT_VERSION}-linux-amd64.tar.gz
cd teleport-api-scripts-${TELEPORT_VERSION}-linux-amd64
./teleport-tpr-tracker -proxy <your-proxy>:443
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
GOOS=windows GOARCH=amd64 make build   # produces teleport-tpr-tracker.exe
```

## Customization

### Common Customizations

All customizations are made by modifying the configuration variables at the top of the script:

**Change update frequency:**
```go
updateInterval = 30 * time.Minute  // Update every 30 minutes instead of 1 hour (default: 1hr)
```

**Adjust data retention:**
```go
dataRetentionDays = 90  // Keep 90 days of historical data instead of 30 (default: 30 days)
```

**Optimize for large clusters:**
```go
eventBatchSize = 10000  // Increase batch size for better performance (default: 5000)
```

## Billing Cycles

Teleport bills against monthly cycles anchored to a customer-specific day, not
the 1st of each month. To append a per-cycle history table to each report (so
it lines up with the "Usage History" view in Teleport Cloud), pass
`-billing-day` with your anchor day (1-31):

```bash
# Aligned to cycles starting on the 7th of each month (e.g. 7 May - 6 Jun)
bash ./run.sh -p teleport.example.com:443 -t -b 7

# Include 5 completed cycles in addition to the in-progress one (default: 3)
bash ./run.sh -p teleport.example.com:443 -t -b 7 -c 5
```

When `-billing-day` is set, each report adds a `BILLING CYCLE HISTORY` section
(or `cycle_history` array in JSON) with one row per cycle. Per-cycle resource
counts are the **peak** (`MAX`) within the cycle window — each row in the
SQLite history is a point-in-time snapshot, so the peak is the most defensible
single number to compare against the portal's per-cycle figure. SPIFFE ID
counts are summed across the cycle.

Anchor days that exceed a given month's length (e.g. 31 in February) are
clamped to the last day of that month. All cycle math is in UTC.

Caveat: per-cycle history is bounded by what's in the SQLite database. If you
request `-cycles N` spanning more than `dataRetentionDays` (default 30),
older cycles will be empty until the tracker has been running long enough.
Bump `dataRetentionDays` in the source to retain longer history.

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
   ./teleport-tpr-tracker -proxy teleport.example.com:443 -identity_file /path/to/your/identity-file
   ```

(for Machine ID, you want the `identity` file in the bot's output directory)

The binary uses the identity file when `-identity_file` is provided; otherwise it falls back to the active `tsh` profile.

## Running

```bash
# port 443 is assumed if you provide no port
./teleport-tpr-tracker -proxy teleport.example.com:443

# Output as JSON instead of text
./teleport-tpr-tracker -proxy teleport.example.com:443 -format json

# Append per-cycle history aligned to billing cycles starting on the 7th
./teleport-tpr-tracker -proxy teleport.example.com:443 -billing-day 7 -cycles 6
```

Before connecting, the binary performs a couple of preflight checks: it probes
`https://<proxy>/v1/webapi/find` for reachability, and (when no `-identity_file`
is given) verifies that the active `tsh` profile points at the same proxy and
hasn't expired. Failures produce a clear message with the exact `tsh login`
command to run.

### Running mau and tpr together

`teleport-tpr-tracker` is a long-lived service; `teleport-mau-tracker` is
one-shot. Run them separately — typically the TPR tracker as a service and the
MAU tracker on demand:

```bash
# In one terminal (or backgrounded / under systemd / in Docker)
./teleport-tpr-tracker -proxy teleport.example.com:443

# In another terminal whenever you want a fresh MAU snapshot
./teleport-mau-tracker -proxy teleport.example.com:443
```

The TPR tracker will:
1. Connect to your Teleport cluster
2. Perform initial resource discovery
3. Start continuous monitoring with periodic updates
4. Generate reports at each update interval
5. Run indefinitely until manually stopped

**Note**: This is designed to run as a long-lived service. Use process management tools like systemd, supervisor, or Docker for production deployments.

## Building and Containerizing

### Building a Binary

To create a standalone binary for deployment:

```bash
# Build for current platform
go build -o teleport-tpr-tracker tpr.go

# Cross-compile for any supported platform (pure Go, no C toolchain needed)
CGO_ENABLED=0 GOOS=linux  GOARCH=amd64 go build -o teleport-tpr-tracker tpr.go
CGO_ENABLED=0 GOOS=linux  GOARCH=arm64 go build -o teleport-tpr-tracker tpr.go
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -o teleport-tpr-tracker tpr.go

# Run the binary
# Update to use your own proxy address
./teleport-tpr-tracker -proxy teleport.example.com:443
```

### Container Deployment

Create a `Dockerfile` for containerized deployment:

```dockerfile
FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY tpr.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o teleport-tpr-tracker tpr.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /app

# Create directory for data persistence
RUN mkdir -p /app/data

COPY --from=builder /app/teleport-tpr-tracker .

# Volume for persistent data (database, logs, reports)
VOLUME ["/app/data"]

# Update to use your own proxy address
CMD ["./teleport-tpr-tracker", "-proxy", "teleport.example.com:443"]
```

### Docker Compose Example

```yaml
version: '3.8'
services:
  teleport-tpr-tracker:
    build: .
    volumes:
      - ./data:/app/data
      - ./identity-file:/app/identity-file:ro  # Mount identity file if using
    environment:
      - TZ=UTC  # Set timezone for consistent timestamps
    restart: unless-stopped
    # Optional: expose ports if you add a web interface later
    # ports:
    #   - "8080:8080"
```

### Running with Docker

```bash
# Build the container
docker build -t teleport-tpr-tracker .

# Run with volume for data persistence
docker run -d \
  --name teleport-tpr-tracker \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/identity-file:/app/identity-file:ro \
  --restart unless-stopped \
  teleport-tpr-tracker

# View logs
docker logs -f teleport-tpr-tracker

# Stop the container
docker stop teleport-tpr-tracker
```

### Kubernetes Deployment

For Kubernetes environments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: teleport-tpr-tracker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: teleport-tpr-tracker
  template:
    metadata:
      labels:
        app: teleport-tpr-tracker
    spec:
      containers:
      - name: teleport-tpr-tracker
        image: teleport-tpr-tracker:latest
        volumeMounts:
        - name: data-volume
          mountPath: /app/data
        - name: identity-secret
          mountPath: /app/identity-file
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: tpr-tracker-data
      - name: identity-secret
        secret:
          secretName: teleport-identity
```

### Production Considerations

- **Data Persistence**: Mount volumes for `/app/data` to preserve database and reports
- **Identity Files**: Use secrets management for identity files in production
- **Resource Limits**: Set appropriate CPU/memory limits based on cluster size
- **Monitoring**: Add health checks and monitoring for the container
- **Backup**: Regularly backup the SQLite database for historical data
- **Updates**: Plan for rolling updates when modifying configuration

## Output Files

### Reports
- **`Teleport_Usage_Report.json`** (`-format json`)
- **`Teleport_Usage_Report.txt`** (`-format text`)

### Data Storage
- **`teleport_usage_data.db`** - SQLite database with historical TPR and MWI counts
- **`teleport_tracker.log`** - Application logs and debug information

## Report Formats

### JSON Format (`-format json`)
```json
{
  "timestamp": "2025-09-05 14:30:15",
  "tpr": {
    "total": 148,
    "applications": 12,
    "kubernetes": 8,
    "databases": 15,
    "windows_desktops": 5,
    "nodes": 108
  },
  "mwi": {
    "bots": 8,
    "bot_instances": 8,
    "spiffe_ids_issued": 245
  }
}
```

### Text Format (`-format text`)
```
[2025-09-05 14:30:15] Teleport Usage Report
=================================================
TELEPORT PROTECTED RESOURCES (TPR)
-------------------------------------------------
Total TPR: 148
  - Applications: 12
  - Kubernetes Clusters: 8
  - Databases: 15
  - Windows Desktops: 5
  - Nodes: 108

MACHINE & WORKLOAD IDENTITY (MWI)
-------------------------------------------------
Bots: 8
Bot Instances: 8
SPIFFE IDs Issued (this period): 245
=================================================
```

## Understanding Usage Counts

### Teleport Protected Resources (TPR)
- **Total TPR**: Combined count of all protected infrastructure resources
- **Applications**: Number of application servers registered
- **Kubernetes Clusters**: Number of Kubernetes clusters accessible
- **Databases**: Number of database servers registered
- **Windows Desktops**: Number of Windows desktop resources
- **Nodes**: Number of SSH-accessible servers/instances

### Machine & Workload Identity (MWI)
- **Bots**: Number of unique Machine ID bots
- **Bot Instances**: Number of individual bot instances running
- **SPIFFE IDs Issued**: Number of SPIFFE IDs issued during the reporting period

**Important**: These counts represent billable Teleport usage metrics. See [Teleport's billing documentation](https://goteleport.com/docs/usage-billing/) for more details.

## Troubleshooting

### Common Issues

1. **Connection Failed**: Verify your proxy URL and network connectivity
2. **Authentication Failed**: Check your `tsh` login status or identity file path
3. **Database Errors**: Ensure write permissions in the script directory
4. **Missing Resources**: Verify your user has permissions to list all resource types
5. **High Memory Usage**: Adjust `updateInterval` or `dataRetentionDays` for large clusters

Here is a basic example of a role which has the minimum needed permissions to read audit events and resources:

```yaml
kind: role
metadata:
  name: resource-read-role
spec:
  allow:
    app_labels:
      '*': '*'
    db_labels:
      '*': '*'
    kube_labels:
      '*': '*'
    node_labels:
      '*': '*'
    windows_desktop_labels:
      '*': '*'
    rules:
    - resources:
      - event
      verbs:
      - list
      - read
version: v7
```

### Performance Considerations

- Script memory usage scales with cluster size
- Database file grows over time (cleaned up based on `dataRetentionDays` for both TPR and MWI data)
- Frequent updates may impact Teleport API performance
- Consider longer update intervals for very large clusters

## Security Notes

- Identity files contain sensitive credentials - store them securely
- Limit script access to users who need usage visibility
- Consider using Teleport RBAC to restrict resource listing permissions if needed
- Log files may contain sensitive cluster information - protect accordingly

### Command-line flags

```
Usage: teleport-tpr-tracker -proxy <teleport-proxy-address> [flags]

  -proxy           Teleport proxy address (required). :443 assumed if no port.
  -identity_file   Optional identity file path. Falls back to active tsh profile.
  -format          Output format: "text" (default) or "json".
  -billing-day     Billing cycle anchor day (1-31). Aligns reports with Teleport billing cycles.
  -cycles          Number of completed cycles to include (default 3, requires -billing-day).

Examples:
  teleport-tpr-tracker -proxy example.teleport.sh
  teleport-tpr-tracker -proxy example.teleport.sh:443 -identity_file /path/to/identity
  teleport-tpr-tracker -proxy example.teleport.sh -billing-day 7 -cycles 3
```