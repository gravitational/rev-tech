# Teleport JIT Access Request Watcher

An automated policy enforcement system for Teleport Just-in-Time access requests that provides configurable resource limits and environment separation controls.

## Features

- **Auto-approval**: Automatically approves compliant access requests
- **Real-time enforcement**: Configurable polling for near real-time policy enforcement
- **Environment separation**: Prevents users from having conflicting role patterns (configurable)
- **Resource limits**: Enforces maximum number of approved resources per user
- **Smart locking**: Locks older requests when policies are violated
- **Comprehensive logging**: Debug output shows policy decisions and enforcement actions

## Policy Enforcement

### Resource Limits
Users can have a maximum number of approved resources at any time (default: 3). When this limit is exceeded, older requests are locked while the newest requests remain active.

### Role Conflict Detection
Users cannot have roles matching conflicting patterns simultaneously. The system detects conflicts by matching configurable patterns in role names (default: `prod` and `research`).

- Single requests containing roles matching multiple conflict patterns are automatically denied
- Multi-request conflicts result in older requests being locked
- Patterns are case-insensitive and support partial matching

## Requirements

- Go 1.21 or later
- Teleport Machine ID identity with appropriate permissions
- Access to Teleport Auth API

### Required Permissions

Your Machine ID identity requires these permissions:

```yaml
rules:
  - resources: ['access_request']
    verbs: ['list', 'read', 'update']
  - resources: ['lock']
    verbs: ['create', 'read', 'update', 'delete']
```

## Installation

### Build from source

```bash
# Clone the repository
git clone https://github.com/djohns7/Teleport-JIT-Watcher
cd Teleport-JIT-Watcher

# Build for your platform
go build -o watcher main.go

# Cross-compile for Linux (if building on Mac/Windows)
GOOS=linux GOARCH=amd64 go build -o watcher-linux main.go
```

## Usage

### Basic Usage

```bash
# Run with default settings (checks every 30s, max 3 resources, prod/research patterns)
./watcher -p your-teleport.example.com:443 -i /path/to/identity

# Enable debug output
./watcher -p your-teleport.example.com:443 -i /path/to/identity -d

# Faster polling for near real-time (every 10 seconds)
./watcher -p your-teleport.example.com:443 -i /path/to/identity -poll-interval=10s
```

### Custom Conflict Patterns

```bash
# Use custom patterns for dev/staging/prod separation
./watcher -p your-teleport.example.com:443 -i /path/to/identity \
  -conflict-patterns=dev,staging,prod

# Enforce separation between different team environments
./watcher -p your-teleport.example.com:443 -i /path/to/identity \
  -conflict-patterns=team-alpha,team-beta,team-gamma

# Use patterns for region-based separation
./watcher -p your-teleport.example.com:443 -i /path/to/identity \
  -conflict-patterns=us-east,us-west,eu-central
```

### Policy Configuration

```bash
# Only check resource limits (disable conflict checking)
./watcher -p your-teleport.example.com:443 -i /path/to/identity \
  -role-conflicts=false -m=5

# Only check role conflicts (disable resource limits)
./watcher -p your-teleport.example.com:443 -i /path/to/identity \
  -resource-limit=false -conflict-patterns=prod,dev,test

# Custom configuration with all options
./watcher -p your-teleport.example.com:443 -i /path/to/identity \
  -conflict-patterns=production,development \
  -m=10 \
  -poll-interval=5s \
  -d
```

## Command Line Options

| Flag | Description | Default |
|------|-------------|---------|
| `-p, --proxy` | Teleport auth service address (required) | - |
| `-i, --identity-file` | Path to Machine ID identity file (required) | - |
| `-m, --max-resources` | Maximum resources per user | `3` |
| `--conflict-patterns` | Comma-separated patterns for role conflict detection | `prod,research` |
| `--poll-interval` | How often to check for violations | `30s` |
| `--resource-limit` | Enable/disable resource limit checking | `true` |
| `--role-conflicts` | Enable/disable role conflict checking | `true` |
| `-d, --debug` | Enable debug output | `false` |

## Examples

### Production/Development Separation
```bash
# Prevent users from having both production and development access
./watcher -p teleport.company.com:443 -i ./identity \
  -conflict-patterns=prod,dev
```

### Multi-Environment Setup
```bash
# Enforce separation between test, staging, and production
./watcher -p teleport.company.com:443 -i ./identity \
  -conflict-patterns=test,staging,production \
  -m=5
```

### Team-Based Access Control
```bash
# Prevent cross-team access conflicts
./watcher -p teleport.company.com:443 -i ./identity \
  -conflict-patterns="team-infrastructure,team-application,team-security"
```

### Regional Separation
```bash
# Enforce geographic access boundaries
./watcher -p teleport.company.com:443 -i ./identity \
  -conflict-patterns="region-us,region-eu,region-apac" \
  -poll-interval=15s
```

## How It Works

1. **Monitoring**: The watcher polls Teleport at regular intervals for access requests
2. **Auto-Approval**: Pending requests that comply with all policies are automatically approved
3. **Auto-Denial**: Pending requests that violate policies are automatically denied with a reason
4. **Conflict Detection**: Checks if users have roles matching multiple conflict patterns
5. **Resource Counting**: Tracks total approved resources per user
6. **Smart Locking**: When violations are detected, older requests are locked while newer ones remain active
7. **Logging**: All actions are logged with details about policy decisions and enforcement actions
