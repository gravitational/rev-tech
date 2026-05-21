# Teleport Usage Tracking Tools

A collection of Go scripts for monitoring and reporting Teleport usage metrics. These tools help track billable usage and activity, and maintain historical data for capacity planning and billing purposes.

## What's Included

### Monthly Active Users (MAU) Tracker
**File:** `mau.go` | **Documentation:** [MAU_README.md](MAU_README.md)

Tracks user activity across Teleport services, reporting both:
- **Zero Trust Access MAU (ZTAMAU)** - Users accessing protected resources (SSH, Kubernetes, databases, applications, desktops)
- **Identity Governance MAU (IGMAU)** - Users utilizing access requests, access lists, and SAML IdP features

**Use this when:** You need to understand which users are actively using Teleport and how they're using it.

### Protected Resources & Machine Identity Tracker
**File:** `tpr.go` | **Documentation:** [TPR_README.md](TPR_README.md)

Monitors infrastructure and identity usage, reporting:
- **Teleport Protected Resources (TPR)** - Infrastructure resources protected by Teleport (servers, apps, databases, etc.)
- **Machine & Workload Identity (MWI)** - Bot usage and SPIFFE ID issuance

**Use this when:** You need to track infrastructure protection and machine identity usage for billing or capacity planning.

## Quick Start

1. **Check your Teleport cluster's version** (see below).
2. **Download a prebuilt binary** for your platform from the [latest release](https://github.com/gravitational/rev-tech/releases) matching that version (release tags follow `teleport-api-scripts-vX.Y.Z`).
3. **Or build from source**: `cd tools/teleport-api-scripts && make build` (or `make build-for TELEPORT_VERSION=v18.5.1` to pin against a specific Teleport version).
4. **Review the detailed README** for the script you want to use (MAU_README.md or TPR_README.md).

See individual README files for complete configuration options.

### Checking your Teleport cluster's version

The Teleport proxy exposes a public, unauthenticated `/v1/webapi/find` endpoint that returns the cluster's version as JSON. Pick whichever method is most convenient — none require extra tooling beyond what each platform ships with by default.

**Browser (any platform):** open `https://<your-proxy>/v1/webapi/find` and look for the `server_version` field in the response.

**Linux / macOS (bash, no `jq` required):**

```bash
curl -s https://<your-proxy>/v1/webapi/find | grep -o '"server_version":"[^"]*"'
# → "server_version":"18.5.1"
```

**Windows (PowerShell):**

```powershell
(Invoke-RestMethod https://<your-proxy>/v1/webapi/find).server_version
# → 18.5.1
```

Use the version you find here to pick the matching `teleport-api-scripts-vX.Y.Z` release.

## Output

Both scripts generate reports in JSON or text format:
- **MAU Script** → `Teleport_Active_Users.txt` or `Teleport_Active_Users.json`
- **TPR Script** → `Teleport_Usage_Report.txt` or `Teleport_Usage_Report.json`

## Requirements

- Access to a Teleport cluster
- Valid Teleport credentials (active `tsh` profile, or an identity file)
- Network connectivity to your Teleport proxy
- Go 1.24+ only if building from source

## Use Cases

**MAU Script:**
- Understand user adoption and engagement
- Track which Teleport features users are actively using
- Identify access request and governance activity
- Generate monthly active user reports for billing

**TPR Script:**
- Monitor infrastructure protection across your environment
- Track bot and machine identity usage
- Maintain historical resource counts
- Generate continuous usage reports for capacity planning