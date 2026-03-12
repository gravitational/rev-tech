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

## Prerequisites

- Go 1.24+ installed
- Access to a Teleport cluster with audit log read permissions
- Valid Teleport credentials (see [Authentication](#authentication) section below)
- Network connectivity to your Teleport proxy and to github.com/golang.org repositories

## Installation

1. Clone or download the script
2. Run `bash ./run.sh -p teleport.example.com:443` to download the correct API version for your cluster
(replacing `teleport.example.com:443` with your Teleport cluster's proxy address)

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

2. Provide the identity file to the script:
   ```bash
   bash ./run.sh -p teleport.example.com:443 -i /path/to/your/identity-file -m
   ```

(for Machine ID, you want the `identity` file in the bot's output directory)

The script will automatically use the appropriate authentication method based on your settings.

## Running the Script

```bash
# replace teleport.example.com:443 with your own Teleport proxy URL
# port 443 will be assumed if you provide no port
# -m runs the MAU script
bash ./run.sh -p teleport.example.com:443 -m
```

The script will:
1. Connect to your Teleport cluster
2. Download the correct Teleport Go API version for your cluster (this can take a few minutes on initial runs)
3. Fetch events in batches (you'll see progress messages)
4. Process and analyze the data
5. Generate a report file

## Building

### Building a Binary

To create a standalone binary for deployment:

```bash
# Build for current platform
go build -o teleport-mau-tracker mau.go

# Build for Linux (common for containers/servers)
# Change target OS/arch if you're running on Mac/arm64
GOOS=linux GOARCH=amd64 go build -o teleport-mau-tracker mau.go

# Run the binary
# Update to use your own proxy address
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

### Script arguments

```bash
Usage: run.sh -p <teleport proxy address> [-i <identity file path>] [-m] [-t] [-v] [-x]

  -p  Teleport proxy address (required). If no port is specified, :443 is assumed.
  -i  Optional identity file path.
  -m  Run MAU script (mau.go)
  -t  Run TPR script (tpr.go)
  -v  Output version and exit
  -x  Enable debugging information for 'go get'

Examples:
  run.sh -p example.teleport.sh -m
  run.sh -p example.teleport.sh:443 -i /path/to/identity -t
  run.sh -p example.teleport.sh -m -t
```