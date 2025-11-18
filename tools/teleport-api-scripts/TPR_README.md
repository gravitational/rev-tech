# Teleport Protected Resources (TPR) Report Generator

This Go script continuously monitors and tracks Teleport Protected Resources (TPRs) in your cluster. It provides real-time visibility into resource counts across all Teleport service types and maintains historical data for billing and capacity planning purposes.

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

## Prerequisites

- Go 1.19+ installed
- Access to a Teleport cluster with audit log read permissions
- Valid Teleport credentials (see [Authentication](#authentication) section below)
- Network connectivity to your Teleport proxy

## Installation

1. Clone or download the script
2. Install dependencies:
   ```bash
   go mod init teleport-tpr
   go get github.com/gravitational/teleport/api/client
   go get github.com/gravitational/teleport/api/types
   go get github.com/mattn/go-sqlite3
   ```

## Customization

### Required Setup

**You must update `teleportProxyURL`** to point to your Teleport cluster.

### Common Customizations

All customizations are made by modifying the configuration variables at the top of the script:

**Change update frequency:**
```go
updateInterval = 30 * time.Minute  // Update every 30 minutes instead of 1 hour (default: 1hr)
```

**Switch to JSON output:**
```go
reportFormat = "json" // Generate report in JSON format (default: txt)
```

**Adjust data retention:**
```go
dataRetentionDays = 90  // Keep 90 days of historical data instead of 30 (default: 30 days)
```

**Optimize for large clusters:**
```go
eventBatchSize = 10000  // Increase batch size for better performance (default: 5000)
```

**Use identity file authentication:**
```go
useIdentityFile = true // Use static identity file instead of tsh user credentials (default: false)
identityFilePath = "/home/user/teleport-identity" // Path to identity file must be set if `useIdentityFile` is set to `true` above
```

## Authentication

The script automatically handles authentication based on your configuration:

### Option 1: User Profile (Default)
Uses your current `tsh` login session - no additional setup required.

**Note**: This method will eventually fail when your credentials expire unless refreshed.

### Option 2: Identity File (Recommended for automation)
For continuous/automated jobs:

1. Generate an identity file:
   ```bash
   tsh login --auth=your_auth_method --out=identity-file --proxy your_proxy.teleport.sh
   ```

2. Update the configuration variables:
   ```go
   useIdentityFile = true
   identityFilePath = "/path/to/your/identity-file"
   ```

The script will automatically use the appropriate authentication method based on your settings.

## Running the Script

```bash
go run tpr.go
```

The script will:
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

# Build for Linux (common for containers/servers)
GOOS=linux GOARCH=amd64 go build -o teleport-tpr-tracker tpr.go

# Run the binary
./teleport-tpr-tracker
```

### Container Deployment

Create a `Dockerfile` for containerized deployment:

```dockerfile
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY tpr.go .
RUN CGO_ENABLED=1 GOOS=linux go build -a -installsuffix cgo -o teleport-tpr-tracker .

FROM alpine:latest
RUN apk --no-cache add ca-certificates sqlite
WORKDIR /app

# Create directory for data persistence
RUN mkdir -p /app/data

COPY --from=builder /app/teleport-tpr-tracker .

# Volume for persistent data (database, logs, reports)
VOLUME ["/app/data"]

CMD ["./teleport-tpr-tracker"]
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
- **`Teleport_Usage_Report.json`** (if `reportFormat = "json"`)
- **`Teleport_Usage_Report.txt`** (if `reportFormat = "text"`)

### Data Storage
- **`teleport_usage_data.db`** - SQLite database with historical TPR and MWI counts
- **`teleport_tracker.log`** - Application logs and debug information

## Report Formats

### JSON Format (`reportFormat = "json"`)
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

### Text Format (`reportFormat = "text"`)
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