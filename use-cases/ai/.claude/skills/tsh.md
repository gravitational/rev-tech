# tsh -- Teleport Client CLI for Infrastructure Access

tsh is Teleport's client CLI for accessing SSH nodes, databases, Kubernetes clusters, applications, cloud providers, and MCP servers through Teleport's proxy service. It supports interactive login, headless authentication, and non-interactive access via tbot-issued identity files.

**Binary:** `tsh` (Teleport v18+)

---

## Quick Reference

### Login and Session Management

```bash
# Interactive login
tsh login --proxy=proxy.example.com

# Login to a specific cluster
tsh login --proxy=proxy.example.com my-leaf-cluster

# Login with access request
tsh login --proxy=proxy.example.com --request-roles=admin --request-reason="debugging"

# Login and export identity file
tsh login --proxy=proxy.example.com --out=identity.pem

# Login and export in specific format (file, openssh, kubernetes)
tsh login --proxy=proxy.example.com --out=identity.pem --format=openssh

# Login with Kubernetes cluster pre-selected
tsh login --proxy=proxy.example.com --kube-cluster=my-cluster

# Login suppressing browser
tsh login --proxy=proxy.example.com --browser=none

# Check current session status
tsh status
tsh status --format=json

# Logout
tsh logout
```

### Key Login Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--out` | `-o` | Export identity to file |
| `--format` | `-f` | Identity format: file, openssh, kubernetes |
| `--overwrite` | | Overwrite existing identity file |
| `--browser` | | Set to 'none' to suppress browser opening |
| `--scope` | | Pin credentials to a given scope |
| `--kube-cluster` | | Kubernetes cluster to login to during login |
| `--request-roles` | | Roles to request |
| `--request-reason` | | Reason for role request |
| `--request-reviewers` | | Suggested reviewers for role request |
| `--request-nowait` | | Finish without waiting for request resolution |
| `--request-id` | | Login with pre-approved request ID |
| `--verbose` | `-v` | Show extra status information |

### Using Identity Files (tbot / Machine-to-Machine)

```bash
# Use tbot-issued identity file with any tsh command
tsh -i /opt/machine-id/identity --proxy=proxy.example.com ls
tsh -i /opt/machine-id/identity --proxy=proxy.example.com ssh user@host
tsh -i /opt/machine-id/identity --proxy=proxy.example.com kube ls
tsh -i /opt/machine-id/identity --proxy=proxy.example.com db ls

# Or set environment variable
export TELEPORT_IDENTITY_FILE=/opt/machine-id/identity
export TELEPORT_PROXY=proxy.example.com
tsh ls
```

---

## Global Flags

These flags work with ALL tsh commands:

| Flag | Short | Description | Env Var |
|------|-------|-------------|---------|
| `--proxy` | | Teleport proxy address | `$TELEPORT_PROXY` |
| `--identity` | `-i` | Identity file path | `$TELEPORT_IDENTITY_FILE` |
| `--user` | | Teleport user | `$TELEPORT_USER` |
| `--login` | `-l` | Remote host login | `$TELEPORT_LOGIN` |
| `--auth` | | Auth connector name | `$TELEPORT_AUTH` |
| `--headless` | | Headless login (shorthand for --auth=headless) | `$TELEPORT_HEADLESS` |
| `--debug` | `-d` | Verbose logging | `$TELEPORT_DEBUG` |
| `--mfa-mode` | | MFA mode: auto, cross-platform, platform, otp, sso | `$TELEPORT_MFA_MODE` |
| `--ttl` | | Minutes to live for session | |
| `--jumphost` | `-J` | SSH jumphost | |
| `--insecure` | | Skip TLS verification (testing only) | |
| `--relay` | | Teleport relay address | `$TELEPORT_RELAY` |
| `--skip-version-check` | | Skip version checking between server and client | |
| `--os-log` | | Verbose logging to unified logging system (implies --debug) | `$TELEPORT_OS_LOG` |
| `--add-keys-to-agent` | `-k` | Key handling: auto, no, yes, only (default: auto) | `$TELEPORT_ADD_KEYS_TO_AGENT` |
| `--enable-escape-sequences` | | Enable SSH escape sequences (default: true) | |
| `--bind-addr` | | Override host:port for browser login | `$TELEPORT_LOGIN_BIND_ADDR` |
| `--callback` | | Override callback URL for browser login (requires --bind-addr) | |
| `--mlock` | | Memory locking mode: off, auto, best_effort, strict (default: auto) | `$TELEPORT_MLOCK_MODE` |
| `--piv-slot` | | PIV slot for Hardware Key support (e.g. "9d") | `$TELEPORT_PIV_SLOT` |
| `--cert-format` | | SSH certificate format | |

---

## SSH Access

### List and Connect to SSH Nodes

```bash
# List available nodes
tsh ls
tsh ls --format=json
tsh ls --format=names
tsh ls env=prod,team=backend
tsh ls --query='labels["env"] == "prod"'
tsh ls --all  # list across all clusters
tsh ls --verbose  # include node UUIDs
tsh ls --search=webserver

# Resolve an SSH host
tsh resolve hostname
tsh resolve --format=json hostname
tsh resolve --quiet hostname

# SSH to a node
tsh ssh user@hostname
tsh ssh -p 2222 user@hostname

# Execute a command
tsh ssh user@hostname "uname -a"

# Execute on multiple nodes, log output per-node
tsh ssh --log-dir=/tmp/logs user@hostname "uname -a"

# Port forwarding
tsh ssh -L 8080:localhost:80 user@hostname
tsh ssh -D 1080 user@hostname  # SOCKS5
tsh ssh -R 8080:localhost:80 user@hostname  # Remote forwarding

# X11 forwarding
tsh ssh -X user@hostname  # Untrusted (secure)
tsh ssh -Y user@hostname  # Trusted (insecure)

# Copy files
tsh scp local-file.txt user@hostname:/remote/path
tsh scp -r user@hostname:/remote/dir ./local-dir

# SSH with automatic access request
tsh ssh --request-mode=resource --request-reason="debugging" user@hostname

# Moderated sessions
tsh ssh --reason="incident" --invite=bob,alice user@hostname

# With identity file
tsh -i /opt/machine-id/identity --proxy=proxy.example.com ssh user@hostname

# Measure SSH latency
tsh latency ssh user@hostname
```

### Key SSH Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--port` | `-p` | SSH port on remote host |
| `--forward-agent` | `-A` | Forward SSH agent |
| `--forward` | `-L` | Local port forwarding |
| `--dynamic-forward` | `-D` | SOCKS5 dynamic forwarding |
| `--remote-forward` | `-R` | Remote port forwarding |
| `--tty` | `-t` | Allocate TTY |
| `--cluster` | `-c` | Target Teleport cluster ($TELEPORT_CLUSTER) |
| `--no-remote-exec` | `-N` | No remote command (port forwarding only) |
| `--no-resume` | | Disable SSH connection resumption ($TELEPORT_NO_RESUME) |
| `--local` | | Execute command on localhost after connecting |
| `--option` | `-o` | OpenSSH options (config file format) |
| `--x11-untrusted` | `-X` | Untrusted (secure) X11 forwarding |
| `--x11-trusted` | `-Y` | Trusted (insecure) X11 forwarding |
| `--x11-untrusted-timeout` | | Timeout for untrusted X11 forwarding (default: 10m) |
| `--invite` | | Comma-separated list of invited participants |
| `--reason` | | Purpose of the session |
| `--participant-req` | | Show required participants for moderated sessions |
| `--request-reason` | | Reason for access request |
| `--request-mode` | | Auto access request: off, resource, role (default: resource) ($TELEPORT_REQUEST_MODE) |
| `--log-dir` | | Directory to log per-node output (multi-node exec) |
| `--relogin` | | Permit re-authentication on failed command (default: true) |
| `--fork-after-authentication` | `-f` | Run in background after auth completes |
| `--disable-access-request` | | (**Deprecated**) Disable automatic resource access requests |

### Key SCP Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--recursive` | `-r` | Recursive copy of subdirectories |
| `--port` | `-P` | Port to connect to on the remote host (uppercase -P) |
| `--preserve` | `-p` | Preserve access and modification times |
| `--quiet` | `-q` | Quiet mode |
| `--cluster` | `-c` | Specify the Teleport cluster |
| `--no-resume` | | Disable SSH connection resumption |
| `--relogin` | | Permit re-authentication on failed command |

### OpenSSH Configuration

```bash
# Print OpenSSH config for use with ssh command
tsh config
tsh config --port=3022
# Add to ~/.ssh/config to use: ssh user@host.cluster.teleport.sh
```

### Proxy SSH Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--cluster` | `-c` | Specify the Teleport cluster |
| `--no-resume` | | Disable SSH connection resumption |
| `--relogin` | | Permit re-authentication on failed command |

### Key Latency SSH Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--cluster` | `-c` | Specify the Teleport cluster |
| `--no-resume` | | Disable SSH connection resumption ($TELEPORT_NO_RESUME) |

---

## Kubernetes Access

### List and Login to Kubernetes Clusters

```bash
# List available clusters
tsh kube ls
tsh kube ls --format=json
tsh kube ls --query='labels["env"] == "staging"'
tsh kube ls --search=production
tsh kube ls --verbose  # show untruncated labels
tsh kube ls --quiet  # quiet mode
tsh kube ls --cluster=my-leaf-cluster

# Login to a cluster (updates kubeconfig)
tsh kube login my-cluster
tsh kube login my-cluster --namespace=default
tsh kube login my-cluster --set-context-name="{{.ClusterName}}-{{.KubeName}}"

# Login to all clusters
tsh kube login --all

# Use kubectl through tsh
tsh kubectl get pods -A
```

### Key Kube Login Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | | Generate a kubeconfig with every cluster the user has access to (mutually exclusive with --labels/--query) |
| `--namespace` | `-n` | Default Kubernetes namespace |
| `--as` | | Kubernetes user impersonation |
| `--as-groups` | | Kubernetes group impersonation |
| `--cluster` | `-c` | Specify the Teleport cluster |
| `--labels` | | Filter by labels |
| `--query` | | Predicate language query |
| `--set-context-name` | | Custom context name template (default: `{{.ClusterName}}-{{.KubeName}}`) |
| `--disable-access-request` | | Disable automatic resource access requests |
| `--request-reason` | | Reason for requesting access |

### Kubernetes Exec, Join, and Sessions

```bash
# Execute a command in a Kubernetes pod
tsh kube exec -n namespace pod-name -- command
tsh kube exec -t -s -c container-name pod-name -- /bin/bash

# Execute on a deployment
tsh kube exec -n namespace deployment/my-deploy -- command

# Execute from file
tsh kube exec -f pod-spec.yaml -- command

# Join an active Kubernetes session (default mode: observer)
tsh kube join <session-id>
tsh kube join --mode=observer <session-id>
tsh kube join --mode=moderator <session-id>
tsh kube join --cluster=my-leaf-cluster <session-id>
```

### Key Kube Exec Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--container` | `-c` | Container name |
| `--tty` | `-t` | Allocate TTY |
| `--stdin` | `-s` | Pass stdin |
| `--namespace` | `-n` | Kubernetes namespace |
| `--filename` | `-f` | File to use to exec into the resource |
| `--quiet` | `-q` | Only print output from remote session |
| `--invite` | | Comma-separated list of invited participants |
| `--reason` | | Purpose of the session |
| `--participant-req` | | Display required participants for moderated sessions |

### Kubernetes Proxy (Recommended for Automation)

```bash
# Start local proxy, reexec into shell with KUBECONFIG set
tsh proxy kube --exec my-cluster

# Start proxy on specific port
tsh proxy kube my-cluster --port=8443

# Proxy multiple clusters
tsh proxy kube cluster1 cluster2 --port=8443

# With label filtering
tsh proxy kube --labels env=prod --port=8443

# Custom context name
tsh proxy kube my-cluster --set-context-name="{{.ClusterName}}-{{.KubeName}}"
```

### Key Proxy Kube Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--as` | | Kubernetes user impersonation |
| `--as-groups` | | Kubernetes group impersonation |
| `--namespace` | `-n` | Default Kubernetes namespace |
| `--port` | `-p` | Local listener port |
| `--exec` | | Run proxy in background, exec into shell |
| `--exec-cmd` | | Command to execute when --exec is enabled (default: $SHELL or /bin/bash). Implicitly enables exec mode |
| `--exec-arg` | | Arguments to pass to the executed command (can be specified multiple times) |
| `--labels` | | Filter by labels |
| `--query` | | Predicate language query |
| `--set-context-name` | | Custom kubeconfig context name template |
| `--cluster` | `-c` | Specify the Teleport cluster |
| `--format` | `-f` | Format for env var commands: unix, command-prompt, powershell, text |

### Deprecated: tsh kube sessions

`tsh kube sessions` is **deprecated** -- use `tsh sessions ls --kind=kube` instead.

### With tbot Identity (Kubernetes Automation)

tbot's `kubernetes/v2` output produces a kubeconfig directly -- prefer this over `tsh proxy kube` for automated workloads:

```bash
# Use tbot-generated kubeconfig
kubectl --kubeconfig /opt/machine-id/kubeconfig.yaml get pods -A
# Or
export KUBECONFIG=/opt/machine-id/kubeconfig.yaml
kubectl get pods -A
```

For cases where tbot kubeconfig is not available, use tsh with identity file:

```bash
tsh -i /opt/machine-id/identity --proxy=proxy.example.com kube ls
tsh -i /opt/machine-id/identity --proxy=proxy.example.com proxy kube my-cluster --port=8443
```

---

## Database Access

### List and Connect to Databases

```bash
# List available databases
tsh db ls
tsh db ls --format=json
tsh db ls --verbose
tsh db ls env=prod
tsh db ls --search=postgres

# Login to a database (get credentials)
tsh db login --db-user=postgres --db-name=mydb my-postgres
tsh db login --db-user=postgres --db-name=mydb --db-roles=reader my-postgres

# Connect interactively
tsh db connect --db-user=postgres --db-name=mydb my-postgres

# Execute commands across databases
tsh db exec --db-user=postgres --db-name=mydb "SELECT 1" --dbs=db1,db2
tsh db exec --db-user=postgres --db-name=mydb "SELECT 1" --labels env=prod
tsh db exec --db-user=postgres --db-name=mydb "SELECT 1" --parallel=5

# Print environment variables for the configured database
tsh db env my-postgres
tsh db env --format=json my-postgres

# Print connection info (for GUI clients)
tsh db config my-postgres
tsh db config --format=cmd my-postgres

# Logout
tsh db logout my-postgres
```

### Key DB Flags (Common Across db Subcommands)

| Flag | Short | Description |
|------|-------|-------------|
| `--db-user` | `-u` | Database username |
| `--db-name` | `-n` | Database name |
| `--db-roles` | `-r` | Database roles for auto-provisioned user |
| `--labels` | | Filter by labels |
| `--query` | | Predicate language query |
| `--format` | `-f` | Format output (text, json, yaml) |
| `--disable-access-request` | | Disable automatic resource access requests |
| `--request-reason` | | Reason for requesting access |

### Key DB Exec Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--db-user` | `-u` | Database username |
| `--db-name` | `-n` | Database name |
| `--db-roles` | `-r` | Database roles for auto-provisioned user |
| `--dbs` | | Target databases (mutually exclusive with --search/--labels) |
| `--parallel` | | Run commands in parallel (default 1, max 10) |
| `--output-dir` | | Directory to store command output per target |
| `--confirm` | | Confirm selected database services before executing (default: true) |
| `--search` | | Search keywords or phrases |
| `--labels` | | Filter by labels |
| `--cluster` | `-c` | Specify the Teleport cluster |

### Database Proxy

```bash
# Start authenticated tunnel (clients skip auth)
tsh proxy db --tunnel --port=5432 --db-user=postgres --db-name=mydb my-postgres
# Then: psql "host=localhost port=5432 dbname=mydb user=postgres"

# Start TLS proxy (client provides auth)
tsh proxy db --port=5432 my-postgres

# With identity file
tsh -i /opt/machine-id/identity --proxy=proxy.example.com \
  proxy db --tunnel --port=5432 --db-user=postgres --db-name=mydb my-postgres
```

### Key Proxy DB Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--tunnel` | | Open authenticated tunnel (clients skip TLS auth) |
| `--port` | `-p` | Local listener port |
| `--listen` | | Source address (mutually exclusive with --port) |
| `--db-user` | `-u` | Database username |
| `--db-name` | `-n` | Database name |
| `--db-roles` | `-r` | Database roles |
| `--insecure-listen-anywhere` | | Allow non-localhost listening |
| `--cluster` | `-c` | Specify the Teleport cluster |
| `--labels` | | Filter by labels |
| `--query` | | Predicate language query |
| `--disable-access-request` | | Disable automatic resource access requests |
| `--request-reason` | | Reason for requesting access |

---

## Application Access

### List and Login to Applications

```bash
# List available apps
tsh apps ls
tsh apps ls --format=json
tsh apps ls --verbose
tsh apps ls --search=myapp
tsh apps ls --query='labels["env"] == "prod"'

# Login to an app
tsh apps login myapp
tsh apps login myapp --aws-role=arn:aws:iam::123456789012:role/myrole
tsh apps login myapp --azure-identity=my-identity
tsh apps login myapp --gcp-service-account=my-sa
tsh apps login myapp --target-port=8443  # multi-port TCP app
tsh apps login myapp --quiet

# Print app connection info
tsh apps config myapp
tsh apps config --format=curl myapp
tsh apps config --format=uri myapp
tsh apps config --format=json myapp

# Logout
tsh apps logout myapp
```

### Key Apps Ls Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output (text, json, yaml) |
| `--query` | | Predicate language query |
| `--search` | | Search keywords or phrases |
| `--verbose` | `-v` | Show extra information |
| `--all` | `-R` | List across all clusters |

### Key Apps Login Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--aws-role` | | AWS role ARN or name |
| `--azure-identity` | | Azure managed identity |
| `--gcp-service-account` | | GCP service account |
| `--target-port` | | Target port for multi-port TCP apps |
| `--quiet` | `-q` | Quiet mode |

### Key Apps Config Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format: uri, ca, cert, key, curl, json, yaml |

### Application Proxy

```bash
# Start local proxy for web app
tsh proxy app mywebapp --port=8080
# Access at http://localhost:8080

# Multi-port TCP app
tsh proxy app mytcpapp --port=1234:5678
```

### Key Proxy App Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--port` | `-p` | Local listener port (format: port or port:target-port) |
| `--cluster` | `-c` | Specify the Teleport cluster |

---

## Cloud Provider Access

```bash
# AWS CLI through Teleport
tsh apps login --aws-role=myrole myaws
tsh aws s3 ls
tsh aws --app=myaws s3 ls          # specify app name
tsh aws --aws-role=myrole s3 ls    # specify role
tsh aws --exec terraform apply     # run arbitrary commands with AWS credentials

# Azure CLI
tsh apps login --azure-identity=my-id myazure
tsh az vm list
tsh az --app=myazure vm list

# GCP CLI
tsh apps login --gcp-service-account=my-sa mygcp
tsh gcloud compute instances list
tsh gcloud --app=mygcp compute instances list
tsh gsutil ls gs://mybucket
tsh gsutil --app=mygcp ls gs://mybucket

# Cloud proxies (for tools that need local endpoint)
tsh proxy aws --port=8080 --app=myaws
tsh proxy azure --port=8080 --app=myazure
tsh proxy gcloud --port=8080 --app=mygcp
```

### Key Cloud Command Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--app` | | Specify the application name |
| `--aws-role` | | AWS role (tsh aws) |
| `--azure-identity` | | Azure identity (tsh az) |
| `--gcp-service-account` | | GCP service account (tsh gcloud/gsutil) |
| `--exec` | | Run arbitrary commands with cloud credentials (tsh aws) |

### Key Cloud Proxy Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--port` | `-p` | Local listener port |
| `--app` | | Specify the application name |
| `--format` | `-f` | Format for env var commands: unix, command-prompt, powershell, text (proxy aws also supports: athena-odbc, athena-jdbc) |

---

## MCP (Model Context Protocol) Access

### List and Connect to MCP Servers

```bash
# List MCP servers
tsh mcp ls
tsh mcp ls --format=json
tsh mcp ls --verbose
tsh mcp ls --search=myserver
tsh mcp ls --query='labels["env"] == "dev"'
tsh mcp ls env=prod

# Connect via stdio (for Claude Desktop, Cursor, etc.)
tsh mcp connect my-mcp-server

# Connect with identity file (automation)
tsh mcp connect -i /opt/machine-id/identity --proxy=proxy.example.com my-mcp-server

# Start HTTP proxy for streamable-HTTP MCP servers
tsh proxy mcp myapp --port=8080
tsh proxy mcp myapp --port=8080 --cluster=my-leaf-cluster
```

### Key MCP Ls Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output (text, json, yaml) |
| `--query` | | Predicate language query |
| `--search` | | Search keywords or phrases |
| `--verbose` | `-v` | Show extra information |

### Key MCP Connect Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--auto-reconnect` | | Auto-reconnect on interruption (default: true) |
| `--header` | `-H` | Extra custom headers for streamable HTTP MCP servers |

### Configure MCP Clients

```bash
# Auto-configure Claude Desktop
tsh mcp config --all --client-config=claude

# Auto-configure Cursor
tsh mcp config --all --client-config=cursor

# Generate VSCode-format config
tsh mcp config --all --format=vscode

# Configure specific server with labels
tsh mcp config --labels env=dev --client-config=claude

# Add to Claude Code project
tsh mcp config --all --client-config=<project>/.mcp.json

# Configure database as MCP server
tsh mcp db config --db-user=postgres --db-name=employees --client-config=claude postgres-dev

# Overwrite existing MCP config entry
tsh mcp db config --db-user=postgres --db-name=employees --overwrite --client-config=claude postgres-dev
```

### MCP Client Configuration JSON

For programmatic integration, use this pattern:

```json
{
    "mcpServers": {
        "teleport-mcp": {
            "command": "tsh",
            "args": [
                "mcp", "connect",
                "-i", "/opt/machine-id/identity",
                "--proxy", "example.teleport.sh:443",
                "my-mcp-server"
            ]
        }
    }
}
```

### Key MCP Config Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-R` | Select all MCP servers (mutually exclusive with --labels/--query) |
| `--labels` | | Filter by labels |
| `--query` | | Predicate language query |
| `--client-config` | | Target: "claude", "cursor", or JSON file path ($TELEPORT_MCP_CLIENT_CONFIG) |
| `--format` | | Config format: claude, vscode, cursor (inferred from file if not provided) |
| `--auto-reconnect` | | Auto-reconnect on interruption (default: true) |
| `--header` | `-H` | Extra custom headers for streamable HTTP MCP servers |
| `--json-format` | | JSON format: pretty, compact, auto, none ($TELEPORT_MCP_CONFIG_JSON_FORMAT) |

### Key MCP DB Config Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--client-config` | | Target: "claude", "cursor", or JSON file path ($TELEPORT_MCP_CLIENT_CONFIG) |
| `--db-user` | `-u` | Database username |
| `--db-name` | `-n` | Database name |
| `--overwrite` | | Overwrite existing config entry |
| `--format` | | Config format: claude, vscode, cursor |
| `--json-format` | | JSON format: pretty, compact, auto, none ($TELEPORT_MCP_CONFIG_JSON_FORMAT) |

### Key Proxy MCP Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--port` | `-p` | Local listener port |
| `--cluster` | `-c` | Specify the Teleport cluster |

---

## Proxy Commands Summary

| Command | Purpose |
|---------|---------|
| `tsh proxy ssh` | Local TLS proxy for SSH (single-port mode) |
| `tsh proxy db` | Local proxy for database connections |
| `tsh proxy app` | Local proxy for HTTP/TCP applications |
| `tsh proxy kube` | Local proxy for Kubernetes, generates kubeconfig |
| `tsh proxy mcp` | Local proxy for streamable-HTTP MCP servers |
| `tsh proxy aws` | Local proxy for AWS API access |
| `tsh proxy azure` | Local proxy for Azure API access |
| `tsh proxy gcloud` | Local proxy for GCP API access |

---

## Access Requests (Programmatic)

### Create and Manage Requests

```bash
# Search for requestable resources
tsh request search --kind=node
tsh request search --kind=kube_cluster
tsh request search --kind=db
tsh request search --kind=app
tsh request search --kind=windows_desktop
tsh request search --kind=git_server
tsh request search --kind=kube_resource --kube-cluster=my-cluster --kube-kind=pods
tsh request search --roles  # list requestable roles instead

# Create access request for roles
tsh request create --roles=admin --reason="incident response"
tsh request create --roles=admin --reason="incident" --reviewers=bob,alice

# Create access request for specific resources
tsh request create --resource=/cluster/node/uuid --reason="debugging"

# Create with scheduling and TTL options
tsh request create --roles=admin --reason="deploy" \
  --assume-start-time=2024-01-15T10:00:00Z \
  --max-duration=4h \
  --request-ttl=1h \
  --session-ttl=8h

# List requests
tsh request ls
tsh request ls --my-requests
tsh request ls --reviewable
tsh request ls --suggested
tsh request ls --format=json

# Show request details
tsh request show <request-id>
tsh request show --format=json <request-id>

# Review a request (as reviewer)
tsh request review --approve --reason="approved" <request-id>
tsh request review --deny --reason="not needed" <request-id>
tsh request review --approve --assume-start-time=2024-01-15T10:00:00Z <request-id>

# Drop elevated access
tsh request drop
tsh request drop <request-id>
```

### Key Request Create Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--roles` | | Roles to request |
| `--resource` | | Specific resource to request |
| `--reason` | | Reason for requesting access |
| `--reviewers` | | Suggested reviewers |
| `--nowait` | | Finish without waiting for request resolution |
| `--assume-start-time` | | Time roles can be assumed (RFC3339 format) |
| `--max-duration` | | Duration for which access should be granted |
| `--request-ttl` | | Expiration time for the access request itself |
| `--session-ttl` | | Expiration time for the elevated certificate |

### Key Request Search Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--kind` | | Resource kind: node, kube_cluster, db, app, windows_desktop, user_group, saml_idp_service_provider, aws_ic_account, aws_ic_account_assignment, git_server, kube_resource |
| `--roles` | | List requestable roles instead of searching resources |
| `--format` | `-f` | Format output |
| `--labels` | | Filter by labels |
| `--query` | | Predicate language query |
| `--search` | | Search keywords or phrases |
| `--verbose` | `-v` | Show full label output |
| `--kube-cluster` | | Kubernetes cluster to search for Pods |
| `--kube-kind` | | Kubernetes resource kind name (plural) |
| `--kube-api-group` | | Kubernetes API group |
| `--namespace` | | Kubernetes namespace (default: default) |
| `--all-kube-namespaces` | | Search Pods in every namespace |

### Access Request Login Flow

```bash
# Login requesting specific roles
tsh login --proxy=proxy.example.com --request-roles=admin --request-reason="deploy"

# Login with pre-approved request
tsh login --proxy=proxy.example.com --request-id=<request-id>

# Login without waiting for approval
tsh login --proxy=proxy.example.com --request-roles=admin --request-nowait

# SSH with automatic access request
tsh ssh --request-mode=resource --request-reason="debugging" user@hostname
```

---

## Headless Authentication

Enables tsh on remote machines that cannot perform MFA directly. Requires approval from another device.

```bash
# Run command with headless auth
tsh --headless ssh user@host
tsh --headless ls

# Or via login
tsh login --auth=headless

# Or via environment variable
export TELEPORT_HEADLESS=1
tsh ssh user@host
```

**Approving headless requests from another device:**

```bash
tsh headless approve --user=alice --proxy=proxy.example.com <request-id>
tsh headless approve --skip-confirm --user=alice --proxy=proxy.example.com <request-id>
```

### Key Headless Approve Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--skip-confirm` | | Skip confirmation and prompt for MFA immediately (default: false) ($TELEPORT_HEADLESS_SKIP_CONFIRM) |

**Characteristics:**
- Each command requires separate MFA approval
- Private keys held in memory only (never written to disk)
- Certificates have one-minute TTL
- Supported commands: ls, ssh, scp, proxy kube

**When NOT to use headless (prefer tbot instead):**
- CI/CD pipelines
- Automated workloads
- Long-running processes

---

## Session Management

```bash
# List active sessions
tsh sessions ls
tsh sessions ls --kind=ssh
tsh sessions ls --kind=kube
tsh sessions ls --kind=db
tsh sessions ls --kind=app
tsh sessions ls --kind=desktop
tsh sessions ls --format=json

# Join an active session (default mode: observer)
tsh join <session-id>
tsh join --mode=observer <session-id>
tsh join --cluster=my-leaf-cluster <session-id>

# Replay a recorded session
tsh play <session-id>
tsh play --speed=2 --skip-idle-time <session-id>
tsh play --format=json <session-id>
tsh play --cluster=my-leaf-cluster <session-id>

# List recordings
tsh recordings ls
tsh recordings ls --last=24h
tsh recordings ls --format=json
tsh recordings ls --from-utc=2024-01-01 --to-utc=2024-01-31
tsh recordings ls --limit=100

# Export desktop session recording to video
tsh recordings export --out=recording.avi <session-id>
```

### Key Recordings Ls Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output (text, json, yaml) |
| `--last` | | Duration to search back (e.g. 5h30m40s) |
| `--from-utc` | | Start of time range (format 2006-01-02) |
| `--to-utc` | | End of time range |
| `--limit` | | Maximum number of recordings (default: 50) |

---

## Git Access

```bash
# Login to GitHub through Teleport
tsh git login --github-org=myorg
tsh git login --github-org=myorg --force

# List git servers
tsh git ls
tsh git ls --format=json
tsh git ls --search=myrepo
tsh git ls --query='labels["org"] == "myorg"'
tsh git ls env=prod

# Clone repository through Teleport
tsh git clone git@github.com:org/repo.git

# Configure/reset Teleport on a repo
tsh git config update
tsh git config reset
```

### Key Git Login Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--github-org` | | GitHub organization name |
| `--force` | | Force a login (default: false) |

### Key Git Ls Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output (text, json, yaml) |
| `--query` | | Predicate language query |
| `--search` | | Search keywords or phrases |

---

## VNet (Virtual Network)

VNet creates a virtual IP subnet with DNS for transparent TCP application access. Eliminates the need for per-app `tsh proxy app` setup. Available on macOS and Windows.

```bash
# Start VNet (after tsh login)
tsh vnet

# Auto-configure SSH via VNet
tsh vnet-ssh-autoconfig
```

**How it works:**
- Assigns virtual IPs from `100.64.0.0/10` (CGNAT range) to Teleport apps
- Local DNS resolves app names to virtual IPs
- TCP connections are proxied through authenticated Teleport tunnels
- Works with CLI tools, IDEs, browsers, any TCP client

**Considerations:**
- IP range may conflict with Tailscale or other CGNAT users
- Teleport Connect GUI is the preferred VNet client (better MFA prompts)
- `tsh vnet` provides the CLI alternative

---

## Device Trust

```bash
# Enroll this device as a trusted device (requires Teleport Enterprise)
tsh device enroll --token=<enrollment-token>

# Enroll current device (requires device admin privileges)
tsh device enroll --current-device
```

---

## MFA Management

```bash
# List registered MFA devices
tsh mfa ls
tsh mfa ls --format=json
tsh mfa ls --verbose

# Add a new MFA device
tsh mfa add
tsh mfa add --name=my-yubikey --type=WEBAUTHN

# Remove an MFA device
tsh mfa rm <device-name>
```

### Key MFA Add Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--name` | | Name for the new MFA device |
| `--type` | | MFA device type: TOTP, WEBAUTHN |
| `--allow-passwordless` | | Allow passwordless logins |

### Key MFA Ls Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--format` | `-f` | Format output (text, json, yaml) |
| `--verbose` | `-v` | Print more information about MFA devices |

---

## Security and Key Scanning

```bash
# Scan local machine for SSH private keys and report to Teleport
tsh scan keys
tsh scan keys --dirs=/home/user/.ssh,/etc/ssh
tsh scan keys --skip-paths=/home/user/.ssh/known_hosts

# Start PIV key agent (Hardware Key support)
tsh piv agent

# List scopes at which user has assigned privileges
tsh scopes ls
tsh scopes ls --verbose  # show per-scope privilege details
```

---

## Utility Commands

```bash
# Print version
tsh version
tsh version --format=json
tsh version --client  # Client version only, no server needed

# List available Teleport clusters
tsh clusters
tsh clusters --format=json
tsh clusters --quiet
tsh clusters --verbose

# Print session environment variables
tsh env
tsh env --format=json
tsh env --unset  # Print commands to clear env vars

# Update client tools to cluster-configured version
tsh update
tsh update --clear  # Remove locally installed updates
```

---

## Workload Identity / SPIFFE

```bash
# Issue X.509 SVID (legacy command)
tsh svid issue --output=/tmp/svid /svc/my-service
tsh svid issue --output=/tmp/svid --dns-san=my.example.com --ip-san=10.0.0.1 --svid-ttl=1h /svc/my-service
tsh svid issue --output=/tmp/svid --type=x509 /svc/my-service

# Issue with workload identity selector (preferred)
tsh workload-identity issue-x509 --name-selector=my-workload --output=/tmp/svid
tsh workload-identity issue-x509 --label-selector=env=prod,team=backend --output=/tmp/svid
tsh workload-identity issue-x509 --name-selector=my-workload --credential-ttl=2h --output=/tmp/svid
```

### Key SVID Issue Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--output` | | Output directory for SVID files |
| `--dns-san` | | DNS SAN for the SVID |
| `--ip-san` | | IP SAN for the SVID |
| `--svid-ttl` | | TTL for the SVID |
| `--type` | | SVID type (default: x509) |

---

## Resource Filtering

Most `ls` commands support these filtering options:

```bash
# Label filtering
tsh ls env=prod,team=backend
tsh db ls env=staging

# Predicate language queries
tsh ls --query='labels["env"] == "prod" && labels["team"] == "backend"'
tsh kube ls --query='labels["region"] == "us-east-1"'

# Keyword search
tsh ls --search=webserver
tsh db ls --search=postgres

# Cross-cluster listing
tsh ls --all
tsh db ls --all
tsh kube ls --all
tsh apps ls --all
```

---

## Integration with tbot for Kubernetes Deployments

### Pattern: tbot Identity + tsh Commands

For workloads deployed in Kubernetes that need to run tsh commands:

1. Deploy tbot (standalone Deployment) that writes identity to a Kubernetes Secret
2. Mount the Secret in workload pods
3. Use `tsh -i` to consume the identity

```yaml
# Workload pod consuming tbot credentials
volumes:
  - name: tbot-identity
    secret:
      secretName: tbot-out
containers:
  - name: app
    volumeMounts:
      - name: tbot-identity
        mountPath: /identity-output
        readOnly: true
    command:
      - tsh
      - -i
      - /identity-output/identity
      - --proxy
      - proxy.example.com:443
      - ssh
      - user@host
```

### Pattern: tbot Direct Outputs (Preferred)

For Kubernetes, database, and application access, prefer tbot's direct outputs over `tsh proxy`:

| Access Type | tbot Output/Service | Usage |
|-------------|---------------------|-------|
| Kubernetes | `kubernetes/v2` output | `kubectl --kubeconfig /path/kubeconfig.yaml` |
| Database | `database` output | Direct TLS connection with cert/key |
| Database | `database-tunnel` service | Connect to `localhost:PORT` (no TLS client cert needed) |
| Application | `application-tunnel` service | Connect to `localhost:PORT` (no TLS client cert needed) |
| Application | `application` output | Use TLS cert/key with curl/clients |
| SSH | `identity` output | `tsh -i /path/identity ssh user@host` |
| MCP | `identity` output | `tsh mcp connect -i /path/identity server` |

### CI/CD Pipeline Pattern

```bash
# In CI/CD (GitHub Actions, GitLab CI, etc.)
tbot start identity \
  --proxy-server=proxy.example.com:443 \
  --join-method=github \
  --token=github-ci \
  --oneshot \
  --destination=file:///tmp/tbot-out

# Then use tsh with the identity
tsh -i /tmp/tbot-out/identity --proxy=proxy.example.com:443 ssh user@host
tsh -i /tmp/tbot-out/identity --proxy=proxy.example.com:443 kube ls
```

---

## Troubleshooting

### Enable Debug Logging

```bash
tsh --debug ssh user@host
# Or: export TELEPORT_DEBUG=1
```

### Common Issues

**"access denied" or "certificate expired":**
- Check session status: `tsh status`
- Re-login: `tsh login --proxy=proxy.example.com`
- For identity files: verify tbot is running and renewing certificates
- Check certificate TTL: identity files expire (default 1h, max 24h)

**"cluster not found" when accessing leaf cluster:**
- List clusters: `tsh clusters`
- Login to specific cluster: `tsh login my-leaf-cluster`
- Use `--cluster` flag: `tsh ls --cluster=my-leaf-cluster`

**Database proxy connection refused:**
- Ensure `tsh db login` was run before `tsh proxy db`
- Use `--tunnel` flag for authenticated tunnels (simpler client config)
- Check database user/name permissions in Teleport role

**Kubernetes proxy kubeconfig not working:**
- Verify cluster access: `tsh kube ls`
- Re-login to cluster: `tsh kube login my-cluster`
- Check impersonation settings in Teleport role

**Identity file not working:**
- Verify file exists and is readable
- Check it was generated recently (tbot should be renewing)
- Ensure `--proxy` flag is set (identity files do not store proxy address)
- Verify bot role grants access to the target resource

**MCP server not appearing:**
- List MCP servers: `tsh mcp ls`
- Verify role grants `app_labels` matching the MCP server
- Verify role includes `mcp.tools` allowing the needed tools

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TELEPORT_PROXY` | Proxy address (replaces --proxy) |
| `TELEPORT_IDENTITY_FILE` | Identity file path (replaces -i) |
| `TELEPORT_USER` | Teleport username |
| `TELEPORT_LOGIN` | SSH remote login user |
| `TELEPORT_AUTH` | Auth connector name |
| `TELEPORT_HEADLESS` | Enable headless mode (1/true) |
| `TELEPORT_MFA_MODE` | MFA mode |
| `TELEPORT_ADD_KEYS_TO_AGENT` | Key handling: auto, no, yes, only |
| `TELEPORT_MCP_CLIENT_CONFIG` | MCP client config target |
| `TELEPORT_RELAY` | Relay address |
| `TELEPORT_LOGIN_BIND_ADDR` | Override host:port for browser login |
| `TELEPORT_MLOCK_MODE` | Memory locking: off, auto, best_effort, strict |
| `TELEPORT_PIV_SLOT` | PIV slot for Hardware Key support |
| `TELEPORT_NO_RESUME` | Disable SSH connection resumption |
| `TELEPORT_OS_LOG` | Enable OS-level logging (implies debug) |
| `TELEPORT_REQUEST_MODE` | Auto access request mode: off, resource, role |
| `TELEPORT_MCP_CONFIG_JSON_FORMAT` | MCP config JSON format: pretty, compact, auto, none |
| `TELEPORT_DEBUG` | Enable debug logging (1/true) |
| `TELEPORT_CLUSTER` | Root or leaf cluster name selection |
| `TELEPORT_HOME` | tsh configuration and data home directory |
| `TELEPORT_GLOBAL_TSH_CONFIG` | Global tsh config file location override |
| `TELEPORT_HEADLESS_SKIP_CONFIRM` | Skip headless approval confirmation |

---

## When to Use tsh vs tbot Direct Outputs

| Scenario | Use |
|----------|-----|
| Interactive user access | `tsh login` + `tsh proxy *` |
| Remote machine (no MFA) | `tsh --headless` |
| CI/CD pipeline | tbot oneshot + `tsh -i` |
| K8s workload accessing K8s | tbot `kubernetes/v2` output (no tsh needed) |
| K8s workload accessing DB | tbot `database` output or `database-tunnel` service (no tsh needed) |
| K8s workload accessing App | tbot `application-tunnel` service (no tsh needed) |
| K8s workload running SSH | tbot `identity` output + `tsh -i ssh` |
| AI/MCP client (interactive) | `tsh mcp config` or `tsh mcp connect` |
| AI/MCP client (automated) | `tsh mcp connect -i /path/identity` |
| Short-lived manual script | `tctl auth sign` + `tsh -i` |
