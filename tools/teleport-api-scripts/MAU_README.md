# Teleport Monthly Active Users (MAU) Report Generator

This Go script connects to a Teleport cluster to analyze user activity and resource usage over a specified time period. It generates reports tracking both Zero Trust Access (ZTAMAU) and Identity Governance (IGMAU) usage patterns.

## What It Does

The script tracks two categories of Monthly Active Users:

### Zero Trust Access MAU (ZTAMAU)
Users actively accessing protected resources:
- **SSH** - Server access sessions
- **Kubernetes** - Kubectl requests and k8s sessions  
- **Database** - Database connection sessions
- **Application** - Application access sessions
- **Desktop** - Windows desktop sessions

### Identity Governance MAU (IGMAU)
Users utilizing just-in-time access and governance features:
- **Access Requests Created** - Users creating access requests
- **Access Requests Reviewed** - Users reviewing/approving access requests
- **Access List Memberships** - Users receiving roles via access list membership
- **Access List Reviews** - Users reviewing access lists
- **SAML IdP Sessions** - Users authenticating via Teleport SAML IdP

**Important**: Users may appear in both ZTAMAU and IGMAU categories if they use both resource access and governance features.

## Prerequisites

- Go 1.19+ installed
- Access to a Teleport cluster
- Valid Teleport credentials (see Authentication section below)
- Network connectivity to your Teleport proxy

## Installation

1. Clone or download the script
2. Install dependencies:
   ```bash
   go mod init teleport-mau
   go get github.com/gravitational/teleport/api/client
   go get github.com/gravitational/teleport/api/defaults
   go get github.com/gravitational/teleport/api/types
   ```

## Customization

### Required Setup

**You must update `teleportProxyURL`** to point to your Teleport cluster.

### Common Customizations

All customizations are made by modifying the configuration variables at the top of the script:

**Change time range:**
```go
daysBack = 60  // Default is 30 days back
```

**Switch to text or JSON output:**
```go
reportFormat = "json" // Default is text
```

**Optimize for large clusters:**
```go
batchSize = 10000  // Increase batch size for better performance. Default is 5000
```

**Use identity file authentication:**
```go
useIdentityFile = true // Default is false
identityFilePath = "/home/user/teleport-identity"
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
go run mau.go
```

The script will:
1. Connect to your Teleport cluster
2. Fetch events in batches (you'll see progress messages)
3. Process and analyze the data
4. Generate a report file

## Output

### JSON Format (`reportFormat = "json"`)
Creates `Teleport_Active_Users.json` with:
```json
{
  "timestamp": "2025-09-05 11:02:21",
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

### Text Format (`reportFormat = "text"`)
Creates `Teleport_Active_Users.txt` with formatted tables:
```
[2025-09-05 11:02:21] Teleport Active Users Report
=================================================
Total Zero Trust Access MAU (ZTAMAU): 2
Total Identity Governance MAU (IGMAU): 1
Total Successful Logins: 93
=================================================

ZERO TRUST ACCESS (ZTAMAU) - Resource Usage
-------------------------------------------------
User                        Logins    SSH       Kube      DB        App       Desktop 
-------------------------------------------------------------------------------------
user@example.com            27        14        5         0         0         25      
admin                       63        32        142       0         25        9       

IDENTITY GOVERNANCE (IGMAU) - Feature Usage
-------------------------------------------------
User                        Req Created  Req Reviewed  List Member  List Review  SAML IdP
------------------------------------------------------------------------------------------
admin@example.com           5            12            2            3            0
```

## Understanding the Results

### Zero Trust Access MAU (ZTAMAU)
- **Total ZTAMAU**: Users who actively accessed at least one protected resource
- **Total Successful Logins**: All successful login events in the time period
- **Per-User Resource Breakdown**:
  - **Logins**: Number of successful authentication events
  - **SSH**: Server access sessions initiated
  - **Kube**: Kubernetes requests and sessions
  - **DB**: Database connection sessions
  - **App**: Application access sessions  
  - **Desktop**: Windows desktop sessions

### Identity Governance MAU (IGMAU)
- **Total IGMAU**: Users who utilized at least one identity governance feature
- **Per-User Feature Breakdown**:
  - **Req Created**: Access requests created by the user
  - **Req Reviewed**: Access requests reviewed/approved by the user
  - **List Member**: Times user received roles via access list membership
  - **List Review**: Access lists reviewed by the user
  - **SAML IdP**: SAML IdP authentication sessions initiated

**Note**: A single user may appear in both ZTAMAU and IGMAU if they both access resources and use governance features.

## Troubleshooting

### Common Issues

1. **Connection Failed**: Verify your proxy URL and network connectivity
2. **Authentication Failed**: Check your `tsh` login status or identity file path
3. **No Events Found**: Verify the time range and that users have been active
4. **Permission Denied**: Ensure your Teleport user has audit log read permissions

### Performance Considerations

- Large clusters may take several minutes to process
- Increase batch size for better performance on busy clusters
- Consider shorter time ranges for initial testing

## Security Notes

- Identity files contain sensitive credentials - store them securely
- Limit script access to users who need audit log visibility
- Consider using Teleport RBAC to restrict audit access if needed