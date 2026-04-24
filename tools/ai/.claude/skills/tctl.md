# tctl -- Teleport Admin CLI for Cluster Management

tctl is Teleport's administrative CLI for managing cluster resources, users, bots, tokens, certificate authorities, access requests, locks, devices, inventory, SSO connectors, plugins, recordings, alerts, workload identity, and dynamic configuration. It connects to the Teleport Auth Service directly or via the Proxy.

**Binary:** `tctl` (Teleport v18+)
**Documentation:** <https://goteleport.com/docs/reference/cli/tctl/>

---

## Quick Reference

### Cluster Status and Diagnostics

```bash
# Print tctl version
tctl version

# Report cluster status
tctl status

# Report diagnostic information
tctl top http://localhost:3000
tctl top http://localhost:3000 5s
```

### Resource CRUD (Universal)

```bash
# Get resources in YAML
tctl get roles
tctl get role/admin
tctl get users --format=json
tctl get all --with-secrets

# Create or update from file
tctl create -f resource.yaml

# Edit interactively
tctl edit role/admin

# Update resource fields
tctl update rc/remote --set-labels=env=prod
tctl update rc/remote --set-ttl=24h

# Delete a resource
tctl rm role/devs
tctl rm cluster/leaf
```

### Common Admin Tasks

```bash
# Add a user with roles
tctl users add alice --roles=access,editor

# Add a bot for Machine ID
tctl bots add my-bot --roles=access

# Create a node join token
tctl tokens add --type=node --ttl=1h

# Lock a user
tctl lock --user=alice --message="Policy violation" --ttl=24h

# Approve an access request
tctl requests approve <request-id> --reason="Approved"

# Sign an identity file
tctl auth sign --user=alice --out=identity.pem --ttl=8h
```

---

## Global Flags

These flags work with ALL tctl commands:

| Flag | Short | Description | Env Var / Default |
|------|-------|-------------|-------------------|
| `--debug` | `-d` | Enable verbose logging to stderr | |
| `--config` | `-c` | Path to configuration file | `$TELEPORT_CONFIG_FILE` / `/etc/teleport.yaml` |
| `--auth-server` | | Connect to specific auth/proxy address(es) | `$TELEPORT_AUTH_SERVER` / `127.0.0.1:3025` |
| `--identity` | `-i` | Path to identity file for remote connections | `$TELEPORT_IDENTITY_FILE` |
| `--insecure` | | Skip TLS certificate verification (testing only) | |

### Connecting Remotely

```bash
# Connect to remote cluster via proxy
tctl --auth-server=proxy.example.com:443 status

# Connect using identity file (from tbot or tctl auth sign)
tctl -i /path/to/identity --auth-server=proxy.example.com:443 status

# Or via environment variables
export TELEPORT_AUTH_SERVER=proxy.example.com:443
export TELEPORT_IDENTITY_FILE=/path/to/identity
tctl status
```

---

## Resource Management

### `tctl get` -- Print Resource Definitions

```bash
# Get all resources of a type
tctl get roles
tctl get users
tctl get tokens
tctl get nodes
tctl get locks
tctl get bots

# Get a specific resource
tctl get role/admin
tctl get user/alice
tctl get token/my-token

# Output formats
tctl get roles --format=yaml
tctl get roles --format=json
tctl get roles --format=text
tctl get roles --verbose

# Include secrets (e.g., CA private keys)
tctl get cert_authority --with-secrets

# Get all resource types
tctl get all
```

#### Key Get Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--format` | | Output format: yaml, json, text | `yaml` |
| `--with-secrets` | | Include secrets in output | off |
| `--verbose` | `-v` | Verbose table output | off |

#### Supported Resource Types

The following resource kinds can be used with `tctl get`, `tctl rm`, `tctl create`, and `tctl edit`:

| Resource Kind | Aliases | Description |
|---------------|---------|-------------|
| `role` | `roles` | Teleport RBAC roles |
| `user` | `users` | User accounts |
| `connector` | | Auth connectors (github, oidc, saml) |
| `github` | | GitHub auth connector |
| `oidc` | | OIDC auth connector |
| `saml` | | SAML auth connector |
| `token` | `tokens` | Join/invitation tokens |
| `node` | `nodes` | SSH nodes |
| `lock` | `locks` | Session/resource locks |
| `bot` | `bots` | Machine ID bots |
| `app` | `apps` | Application resources |
| `db` | `databases` | Database resources |
| `kube_cluster` | `kube_clusters` | Kubernetes clusters |
| `windows_desktop` | `windows_desktops` | Windows desktops |
| `cert_authority` | `cas` | Certificate authorities |
| `trusted_cluster` | `rc` | Trusted clusters |
| `network_restrictions` | | Network restrictions |
| `access_list` | `access_lists` | Access Lists |
| `login_rule` | `login_rules` | Login rules |
| `device` | `devices` | Trusted devices |
| `installer` | | Installer scripts |
| `ui_config` | | UI configuration |
| `cluster_auth_preference` | `cap` | Auth preference |
| `cluster_networking_config` | | Networking configuration |
| `session_recording_config` | | Session recording configuration |
| `workload_identity` | | Workload identity resources |

### `tctl create` -- Create or Update Resources

```bash
# Create from file
tctl create role.yaml

# Create from stdin
cat role.yaml | tctl create

# Force overwrite if exists
tctl create -f role.yaml
```

#### Key Create Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Overwrite resource if it already exists |

### `tctl edit` -- Edit Resources Interactively

```bash
# Opens resource in $EDITOR
tctl edit role/admin
tctl edit user/alice
tctl edit cluster_auth_preference
```

### `tctl update` -- Update Resource Fields

```bash
# Set labels on a trusted cluster
tctl update rc/remote --set-labels=env=prod,region=us-east

# Set TTL
tctl update rc/remote --set-ttl=24h
```

#### Key Update Flags

| Flag | Description |
|------|-------------|
| `--set-labels` | Set labels (key=value pairs) |
| `--set-ttl` | Set time-to-live |

### `tctl rm` -- Delete Resources

```bash
# Delete by type/name
tctl rm role/devs
tctl rm user/alice
tctl rm token/my-token
tctl rm lock/lock-id
tctl rm cluster/leaf-cluster
```

---

## Users

### `tctl users add` -- Create User Invitation

```bash
# Add user with roles
tctl users add alice --roles=access,editor

# Add with SSH logins
tctl users add alice --roles=access --logins=root,ubuntu

# Add with Kubernetes access
tctl users add alice --roles=access --kubernetes-users=admin --kubernetes-groups=system:masters

# Add with database access
tctl users add alice --roles=access --db-users=postgres --db-names=mydb --db-roles=reader

# Add with cloud provider access
tctl users add alice --roles=access \
  --aws-role-arns=arn:aws:iam::123456789012:role/admin \
  --azure-identities=my-identity \
  --gcp-service-accounts=my-sa@project.iam.gserviceaccount.com

# Add with Windows logins
tctl users add alice --roles=access --windows-logins=Administrator

# Add with MCP tools access
tctl users add alice --roles=access --mcp-tools=tool1,tool2

# Custom token TTL
tctl users add alice --roles=access --ttl=4h

# With host user provisioning
tctl users add alice --roles=access --host-user-uid=1001 --host-user-gid=1001
```

#### Key Users Add Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--roles` | Roles for the new user (required) | |
| `--logins` | Allowed SSH logins | |
| `--windows-logins` | Allowed Windows logins | |
| `--kubernetes-users` | Allowed Kubernetes users | |
| `--kubernetes-groups` | Allowed Kubernetes groups | |
| `--db-users` | Allowed database users | |
| `--db-names` | Allowed database names | |
| `--db-roles` | Database roles for auto provisioning | |
| `--aws-role-arns` | Allowed AWS role ARNs | |
| `--azure-identities` | Allowed Azure identities | |
| `--gcp-service-accounts` | Allowed GCP service accounts | |
| `--mcp-tools` | Allowed MCP tools | |
| `--host-user-uid` | UID for auto provisioned host users | |
| `--host-user-gid` | GID for auto provisioned host users | |
| `--default-relay-addr` | Default relay address for clients | |
| `--ttl` | Token expiration time | `1h` (max `48h`) |

### `tctl users update` -- Update User Account

```bash
# Replace roles
tctl users update alice --set-roles=access,editor,admin

# Replace SSH logins
tctl users update alice --set-logins=root,ubuntu

# Replace database access
tctl users update alice --set-db-users=postgres,reader --set-db-names=mydb,testdb

# Replace Kubernetes access
tctl users update alice --set-kubernetes-users=admin --set-kubernetes-groups=system:masters

# Replace cloud access
tctl users update alice --set-aws-role-arns=arn:aws:iam::123456789012:role/admin

# Replace Windows logins
tctl users update alice --set-windows-logins=Administrator,User

# Set host user provisioning
tctl users update alice --set-host-user-uid=1001 --set-host-user-gid=1001

# Reset host user provisioning
tctl users update alice --set-host-user-uid= --set-host-user-gid=

# Replace MCP tools
tctl users update alice --set-mcp-tools=tool1,tool2

# Set default relay address
tctl users update alice --set-default-relay-addr=relay.example.com:443
```

#### Key Users Update Flags

| Flag | Description |
|------|-------------|
| `--set-roles` | Replace current roles |
| `--set-logins` | Replace current SSH logins |
| `--set-windows-logins` | Replace current Windows logins |
| `--set-kubernetes-users` | Replace current Kubernetes users |
| `--set-kubernetes-groups` | Replace current Kubernetes groups |
| `--set-db-users` | Replace current database users |
| `--set-db-names` | Replace current database names |
| `--set-db-roles` | Replace current database roles |
| `--set-aws-role-arns` | Replace current AWS role ARNs |
| `--set-azure-identities` | Replace current Azure identities |
| `--set-gcp-service-accounts` | Replace current GCP service accounts |
| `--set-mcp-tools` | Replace current allowed MCP tools |
| `--set-host-user-uid` | Set UID for auto provisioned host users (empty to reset) |
| `--set-host-user-gid` | Set GID for auto provisioned host users (empty to reset) |
| `--set-default-relay-addr` | Set default relay address (empty to reset) |

### `tctl users ls` -- List Users

```bash
tctl users ls
```

### `tctl users rm` -- Delete Users

```bash
# Delete a single user
tctl users rm alice

# Delete multiple users (comma-separated)
tctl users rm alice,bob,charlie
```

### `tctl users reset` -- Reset User Password

```bash
# Generate password reset token (local users only)
tctl users reset alice

# Custom TTL
tctl users reset alice --ttl=4h
```

| Flag | Description | Default |
|------|-------------|---------|
| `--ttl` | Token expiration time | `8h` (max `24h`) |

---

## Bots (Machine & Workload Identity)

### `tctl bots add` -- Create Bot

```bash
# Add bot with roles
tctl bots add my-bot --roles=access

# Add bot with multiple roles
tctl bots add my-bot --roles=access,wi-issuer

# Add bot with SSH logins
tctl bots add my-bot --roles=access --logins=root,ubuntu

# Add bot with custom join token TTL
tctl bots add my-bot --roles=access --ttl=1h

# Add bot using an existing token
tctl bots add my-bot --roles=access --token=existing-token

# Set max session TTL
tctl bots add my-bot --roles=access --max-session-ttl=24h
```

#### Key Bots Add Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--roles` | Roles the bot can assume | |
| `--ttl` | TTL for bot join token | |
| `--token` | Name of existing token to use | |
| `--logins` | Allowed SSH logins for bot user | |
| `--max-session-ttl` | Max session TTL for bot's internal identity | `12h` (max `168h`) |

### `tctl bots update` -- Update Bot

```bash
# Replace all roles
tctl bots update my-bot --set-roles=access,editor

# Add roles
tctl bots update my-bot --add-roles=wi-issuer

# Replace logins
tctl bots update my-bot --set-logins=root,ubuntu

# Add logins
tctl bots update my-bot --add-logins=app

# Set max session TTL
tctl bots update my-bot --set-max-session-ttl=24h
```

#### Key Bots Update Flags

| Flag | Description |
|------|-------------|
| `--set-roles` | Replace roles (comma-separated) |
| `--add-roles` | Add roles (comma-separated) |
| `--set-logins` | Replace logins (comma-separated) |
| `--add-logins` | Add logins (comma-separated) |
| `--set-max-session-ttl` | Set max session TTL (max `168h`) |

### `tctl bots ls` -- List Bots

```bash
tctl bots ls
```

### `tctl bots rm` -- Remove Bot

```bash
tctl bots rm my-bot
```

### `tctl bots instances` -- Manage Bot Instances

```bash
# List all bot instances
tctl bots instances list
tctl bots instances list --format=json
tctl bots instances list my-bot

# Filter and sort instances
tctl bots instances list --search=my-bot
tctl bots instances list --query='labels["env"] == "prod"'
tctl bots instances list --sort-index=active_at_latest --sort-order=descending

# Show specific instance
tctl bots instances show my-bot/uuid-here

# Join a new instance onto an existing bot
tctl bots instances add my-bot
tctl bots instances add my-bot --token=existing-token --format=json
```

#### Key Bots Instances List Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--format` | Output format: text, json | `text` |
| `--search` | Fuzzy search query | |
| `--query` | Predicate language expression | |
| `--sort-index` | Sort by: bot_name, active_at_latest, version_latest, host_name_latest | `bot_name` |
| `--sort-order` | Sort order: ascending, descending | `ascending` |

---

## Tokens

### `tctl tokens add` -- Create Invitation Token

```bash
# Node join token
tctl tokens add --type=node
tctl tokens add --type=node --ttl=1h

# Bot join token
tctl tokens add --type=bot --bot-name=my-bot --ttl=30m

# Multi-type token
tctl tokens add --type=node,app,db

# App join token with app details
tctl tokens add --type=app --app-name=grafana --app-uri=http://localhost:3000

# Database join token
tctl tokens add --type=db --db-name=mydb --db-protocol=postgres --db-uri=localhost:5432

# Proxy token
tctl tokens add --type=proxy

# Kubernetes and discovery token
tctl tokens add --type=kube,discovery

# With specific value
tctl tokens add --type=node --value=my-secret-token

# With labels
tctl tokens add --type=node --labels=env=prod,region=us-east

# Output as JSON
tctl tokens add --type=node --format=json
```

#### Key Tokens Add Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--type` | Token type(s): node, proxy, app, db, kube, windowsdesktop, discovery, bot (required) | |
| `--value` | Override random token with specific value | |
| `--labels` | Token labels (key=value pairs) | |
| `--ttl` | Token expiration | `30m` |
| `--app-name` | Application name | `example-app` |
| `--app-uri` | Application URI | `http://localhost:8080` |
| `--db-name` | Database name | |
| `--db-protocol` | Database protocol (postgres, mysql, mongodb, oracle, cockroachdb, redis, snowflake, sqlserver, cassandra, elasticsearch, opensearch, dynamodb, clickhouse, clickhouse-http, spanner) | |
| `--db-uri` | Database address | |
| `--format` | Output format: text, json, yaml | |

### `tctl tokens ls` -- List Tokens

```bash
tctl tokens ls
tctl tokens ls --format=json
tctl tokens ls --with-secrets
tctl tokens ls --labels=env=prod
```

#### Key Tokens Ls Flags

| Flag | Description |
|------|-------------|
| `--format` | Output format: text, json, yaml |
| `--with-secrets` | Show token values without redaction |
| `--labels` | Filter by labels |

### `tctl tokens rm` -- Delete Token

```bash
tctl tokens rm my-token
```

### `tctl tokens configure-kube` -- Configure Kubernetes Join Token

```bash
# Auto-detect join method
tctl tokens configure-kube --service-account=tbot -n teleport

# Specify join method
tctl tokens configure-kube --service-account=tbot -n teleport --join-with=oidc

# For a bot
tctl tokens configure-kube --service-account=tbot -n teleport --bot=my-bot

# Custom output file
tctl tokens configure-kube --service-account=tbot -o values.yaml

# Force overwrite existing token
tctl tokens configure-kube --service-account=tbot -f
```

#### Key Tokens Configure-Kube Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--service-account` | `-s` | Kubernetes Service Account name (required) | |
| `--namespace` | `-n` | Service Account namespace | `teleport` |
| `--join-with` | `-j` | Joining type: oidc, jwks, auto | `auto` |
| `--out` | `-o` | Output file path | `./values.yaml` |
| `--context` | | Kubernetes context | active context |
| `--cluster-name` | | Kubernetes cluster name | context name |
| `--token-name` | | Optional join token name | |
| `--bot` | | Bot name (overrides --type) | |
| `--type` | | Token type(s) | `kube,app,discovery` |
| `--update-group` | | Optional update group | |
| `--force` | `-f` | Force creation even if token exists | off |

---

## Nodes

### `tctl nodes add` -- Generate Node Invitation

```bash
# Generate node join token
tctl nodes add

# With specific roles
tctl nodes add --roles=node,app

# Custom TTL
tctl nodes add --ttl=1h

# Override with specific token value
tctl nodes add --token=my-node-token
```

#### Key Nodes Add Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--roles` | Comma-separated roles for new node | `node` |
| `--ttl` | Time to live for generated token | `30m` |
| `--token` | Override random token with specified value | |

### `tctl nodes ls` -- List SSH Nodes

```bash
tctl nodes ls
tctl nodes ls --format=yaml
tctl nodes ls --verbose
tctl nodes ls env=prod
tctl nodes ls --search=webserver
tctl nodes ls --query='labels["env"] == "prod"'
```

#### Key Nodes Ls Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--format` | | Output format: text, yaml | `text` |
| `--verbose` | `-v` | Verbose table output, shows full labels | off |
| `--search` | | Comma-separated search keywords | |
| `--query` | | Predicate language query | |

---

## Certificate Authorities

### `tctl auth export` -- Export CA Certificates

```bash
# Export all CAs
tctl auth export

# Export specific type
tctl auth export --type=host
tctl auth export --type=user
tctl auth export --type=tls-host
tctl auth export --type=tls-user
tctl auth export --type=db
tctl auth export --type=openssh
tctl auth export --type=tls-spiffe

# Export to file
tctl auth export --type=host --out=/tmp/host-ca

# Filter by fingerprint
tctl auth export --fingerprint=sha256:...

# Include private keys
tctl auth export --keys

# Export for integrations
tctl auth export --type=github --integration=my-github
tctl auth export --type=awsra
```

#### Key Auth Export Flags

| Flag | Description |
|------|-------------|
| `--type` | Certificate type: user, host, tls-host, tls-user, tls-user-der, tls-spiffe, windows, db, db-der, db-client, db-client-der, openssh, saml-idp, github, awsra |
| `--out` | Write to files with given path prefix |
| `--keys` | Print private keys |
| `--fingerprint` | Filter authority by fingerprint |
| `--compat` | Export certificates compatible with specific version |
| `--integration` | Integration name (for github CAs) |

### `tctl auth sign` -- Create Identity Files

```bash
# Sign identity for a user
tctl auth sign --user=alice --out=alice-identity.pem

# With custom TTL
tctl auth sign --user=alice --out=identity.pem --ttl=8h

# OpenSSH format
tctl auth sign --user=alice --out=alice --format=openssh

# Kubernetes kubeconfig
tctl auth sign --user=alice --out=kubeconfig --format=kubernetes \
  --proxy=proxy.example.com --kube-cluster-name=my-cluster

# Leaf cluster kubeconfig
tctl auth sign --user=alice --out=kubeconfig --format=kubernetes \
  --proxy=proxy.example.com --kube-cluster-name=my-cluster --leaf-cluster=leaf

# Database certificate
tctl auth sign --user=alice --out=db-cert --format=db \
  --db-service=my-postgres --db-user=reader --db-name=mydb

# MongoDB certificate
tctl auth sign --user=alice --out=mongo-cert --format=mongodb \
  --db-service=my-mongo

# Application identity
tctl auth sign --user=alice --out=app-cert --format=tls --app-name=grafana

# Windows certificate
tctl auth sign --out=win-cert --format=windows \
  --windows-user=Administrator --windows-domain=example.com

# Host certificate
tctl auth sign --host=node1.example.com --out=host-cert

# Overwrite existing files
tctl auth sign --user=alice --out=identity.pem --overwrite

# Stream as tarball
tctl auth sign --user=alice --out=identity --tar
```

#### Key Auth Sign Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--user` | | Teleport user name | |
| `--host` | | Teleport host name | |
| `--out` | `-o` | Output file path (required) | |
| `--format` | | Format: file, openssh, tls, kubernetes, db, windows, mongodb, cockroachdb, redis, snowflake, elasticsearch, cassandra, scylla, oracle | `file` |
| `--ttl` | | TTL for generated certificate | `12h` |
| `--proxy` | | Proxy address (used with kubernetes format) | |
| `--overwrite` | | Overwrite existing destination files | prompt |
| `--tar` | | Create tarball and stream to stdout | off |
| `--leaf-cluster` | | Leaf cluster for kubernetes format | |
| `--kube-cluster-name` | | Kubernetes cluster name | |
| `--app-name` | | Application name | |
| `--db-service` | | Database service name | |
| `--db-user` | | Database user | |
| `--db-name` | | Database name | |
| `--windows-user` | | Windows user | |
| `--windows-domain` | | AD domain for cert validity | |
| `--windows-pki-domain` | | AD domain for CRLs | |
| `--windows-sid` | | Optional Security Identifier | |
| `--omit-cdp` | | Omit CRL Distribution Points (windows) | off |
| `--compat` | | OpenSSH compatibility flag | |

### `tctl auth rotate` -- Rotate Certificate Authorities

```bash
# Interactive rotation
tctl auth rotate --interactive

# Manual rotation (step by step)
tctl auth rotate --manual --type=host --phase=init
tctl auth rotate --manual --type=host --phase=update_clients
tctl auth rotate --manual --type=host --phase=update_servers
tctl auth rotate --manual --type=host --phase=standby

# Rollback
tctl auth rotate --manual --type=host --phase=rollback

# Custom grace period
tctl auth rotate --type=user --grace-period=48h
```

#### Key Auth Rotate Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--interactive` | Enable interactive mode | |
| `--manual` | Activate manual rotation | off |
| `--type` | CA type: host, user, db, db_client, openssh, jwt, saml_idp, oidc_idp, spiffe, windows, okta, awsra, bound_keypair | |
| `--phase` | Target phase: init, standby, update_clients, update_servers, rollback | |
| `--grace-period` | Grace period for previous CA signatures | `30h` |

### `tctl auth ls` -- List Auth Servers

```bash
tctl auth ls
tctl auth ls --format=json
tctl auth ls --format=text
```

### `tctl auth crl` -- Export Empty Certificate Revocation List

```bash
tctl auth crl --type=host
tctl auth crl --type=db --out=/tmp/crl
tctl auth crl --type=db_client
tctl auth crl --type=user
```

#### Key Auth CRL Flags

| Flag | Description |
|------|-------------|
| `--type` | CA type: host, db, db_client, user (required) |
| `--out` | Write to files with given path prefix |

---

## Access Requests

### `tctl requests ls` -- List Access Requests

```bash
tctl requests ls
tctl requests ls --sort-index=state
tctl requests ls --sort-order=ascending
```

#### Key Requests Ls Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--sort-index` | Sort by: created, state | `created` |
| `--sort-order` | Sort order: ascending, descending | `descending` |

### `tctl requests get` -- Show Request Details

```bash
tctl requests get <request-id>
```

### `tctl requests approve` -- Approve Request

```bash
tctl requests approve <request-id>
tctl requests approve <request-id> --reason="Approved for maintenance"
tctl requests approve <request-id> --roles=admin
tctl requests approve <request-id> --delegator=bob
tctl requests approve <request-id> --annotations=ticket=JIRA-123
tctl requests approve <request-id> --assume-start-time=2024-01-15T10:00:00Z
```

#### Key Requests Approve Flags

| Flag | Description |
|------|-------------|
| `--delegator` | Optional delegating identity |
| `--reason` | Optional reason message |
| `--annotations` | Resolution attributes (key=value pairs) |
| `--roles` | Override requested roles |
| `--assume-start-time` | Time roles can be assumed (RFC3339) |

### `tctl requests deny` -- Deny Request

```bash
tctl requests deny <request-id>
tctl requests deny <request-id> --reason="Not authorized"
tctl requests deny <request-id> --delegator=bob --annotations=policy=denied
```

#### Key Requests Deny Flags

| Flag | Description |
|------|-------------|
| `--delegator` | Optional delegating identity |
| `--reason` | Optional reason message |
| `--annotations` | Resolution annotations (key=value pairs) |

### `tctl requests create` -- Create Request

```bash
# Create role request
tctl requests create alice --roles=admin --reason="Deploy"

# Create resource request
tctl requests create alice --resource=/cluster/node/uuid

# Dry run (validate without creating)
tctl requests create alice --roles=admin --dry-run
```

#### Key Requests Create Flags

| Flag | Description |
|------|-------------|
| `--roles` | Roles to request |
| `--resource` | Resource ID to request (repeatable) |
| `--reason` | Optional reason message |
| `--dry-run` | Validate without generating the request |

### `tctl requests review` -- Review Request

```bash
tctl requests review <request-id> --author=bob --approve
tctl requests review <request-id> --author=bob --deny
```

#### Key Requests Review Flags

| Flag | Description |
|------|-------------|
| `--author` | Username of reviewer (required) |
| `--approve` | Review proposes approval |
| `--deny` | Review proposes denial |

### `tctl requests rm` -- Delete Request

```bash
tctl requests rm <request-id>
tctl requests rm <request-id> --force
```

| Flag | Short | Description |
|------|-------|-------------|
| `--force` | `-f` | Force deletion of an active Access Request |

---

## Locks

### `tctl lock` -- Create a Lock

```bash
# Lock a user
tctl lock --user=alice --message="Account suspended" --ttl=24h

# Lock a role
tctl lock --role=admin --message="Role under review" --expires=2024-12-31T23:59:59Z

# Lock a specific login
tctl lock --login=root --ttl=1h

# Lock an MFA device
tctl lock --mfa-device=<device-uuid> --message="Lost device"

# Lock a Windows desktop
tctl lock --windows-desktop=win-server-1 --ttl=48h

# Lock an access request
tctl lock --access-request=<request-uuid>

# Lock a trusted device
tctl lock --device=<device-uuid> --message="Compromised device"

# Lock a server
tctl lock --server-id=<server-uuid> --message="Server maintenance"

# Lock a bot instance
tctl lock --bot-instance-id=<bot-uuid>

# Lock a join token
tctl lock --join-token=my-token --message="Token compromised"
```

#### Key Lock Flags

| Flag | Description |
|------|-------------|
| `--user` | Teleport user to disable |
| `--role` | Teleport role to disable |
| `--login` | Local UNIX user to disable |
| `--mfa-device` | UUID of MFA device to disable |
| `--windows-desktop` | Windows desktop name to disable |
| `--access-request` | UUID of Access Request to disable |
| `--device` | UUID of trusted device to disable |
| `--server-id` | UUID of Teleport server to disable |
| `--bot-instance-id` | UUID of bot instance to disable |
| `--join-token` | Bot join token name to disable |
| `--message` | Message for locked-out users |
| `--expires` | Expiration time (RFC3339) |
| `--ttl` | Duration until lock expires |

---

## Alerts

### `tctl alerts list` -- List Alerts

```bash
tctl alerts list
tctl alerts list --verbose
tctl alerts list --labels=severity=high
tctl alerts list --format=json
```

#### Key Alerts List Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--verbose` | `-v` | Show detailed info including acknowledged alerts | off |
| `--labels` | | Filter by labels | |
| `--format` | | Output format: text, json, yaml | `text` |

### `tctl alerts create` -- Create Alert

```bash
tctl alerts create "Scheduled maintenance tonight"
tctl alerts create "Critical: Auth server upgrade required" --severity=high --ttl=48h
tctl alerts create "New policy" --labels=team=security --severity=medium
```

#### Key Alerts Create Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--ttl` | Expiration duration | `24h` |
| `--severity` | Alert severity: low, medium, high | `low` |
| `--labels` | Labels to attach | |

### `tctl alerts delete` -- Delete Alert

```bash
tctl alerts delete <alert-id>
```

### `tctl alerts ack` -- Acknowledge Alert

```bash
# Acknowledge an alert
tctl alerts ack <alert-id>
tctl alerts ack <alert-id> --reason="Investigating" --ttl=4h

# Clear acknowledgment
tctl alerts ack <alert-id> --clear

# List acknowledged alerts
tctl alerts ack ls
```

#### Key Alerts Ack Flags

| Flag | Description |
|------|-------------|
| `--ttl` | Duration to acknowledge for |
| `--clear` | Clear the acknowledgment |
| `--reason` | Reason for acknowledging |
| `--format` | Output format: text, json, yaml |

---

## Devices (Device Trust)

### `tctl devices add` -- Register Device

```bash
# Register by OS and asset tag
tctl devices add --os=macos --asset-tag=C02XG2JGH

# Register current device
tctl devices add --current-device

# Register and create enrollment token
tctl devices add --os=macos --asset-tag=C02XG2JGH --enroll --enroll-ttl=1h

# Output as JSON
tctl devices add --os=windows --asset-tag=ASSET123 --format=json
```

#### Key Devices Add Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--os` | Operating system | |
| `--asset-tag` | Inventory identifier (e.g., Mac serial) | |
| `--current-device` | Register current device | off |
| `--enroll` | Create device enrollment token | off |
| `--enroll-ttl` | Enrollment token duration | |
| `--format` | Output format: text, json, yaml | `text` |

### `tctl devices ls` -- List Devices

```bash
tctl devices ls
tctl devices ls --format=json
```

### `tctl devices rm` -- Remove Device

```bash
tctl devices rm --device-id=<uuid>
tctl devices rm --asset-tag=C02XG2JGH
tctl devices rm --current-device
```

### `tctl devices enroll` -- Create Enrollment Token

```bash
tctl devices enroll --device-id=<uuid>
tctl devices enroll --asset-tag=C02XG2JGH --ttl=1h
tctl devices enroll --current-device
```

### `tctl devices lock` -- Lock Device

```bash
tctl devices lock --device-id=<uuid> --message="Lost device"
tctl devices lock --asset-tag=C02XG2JGH --ttl=48h
tctl devices lock --current-device --expires=2024-12-31T23:59:59Z
```

---

## Inventory

### `tctl inventory status` -- Inventory Status

```bash
tctl inventory status
tctl inventory status --connected
tctl inventory status --format=json
```

#### Key Inventory Status Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--connected` | Show locally connected instances summary | off |
| `--format` | Output format: text, json | `text` |

### `tctl inventory list` -- List Instances

```bash
# List all instances
tctl inventory list
tctl inventory ls

# Filter by version
tctl inventory ls --older-than=v17.0.0
tctl inventory ls --newer-than=v18.0.0
tctl inventory ls --exact-version=v18.7.0

# Filter by service type
tctl inventory ls --services=node
tctl inventory ls --services=proxy,auth

# Filter by upgrader
tctl inventory ls --upgrader=kube
tctl inventory ls --upgrader=unit
tctl inventory ls --upgrader=none

# Filter by update group
tctl inventory ls --update-group=canary

# Output as JSON
tctl inventory ls --format=json
```

#### Key Inventory List Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--older-than` | Filter for older versions | |
| `--newer-than` | Filter for newer versions | |
| `--exact-version` | Filter by exact version | |
| `--services` | Filter by service: node, kube, proxy, auth, etc. | |
| `--format` | Output format: text, json | `text` |
| `--upgrader` | Filter by upgrader: kube, unit, none | |
| `--update-group` | Filter by update group | |

### `tctl inventory ping` -- Ping Instance

```bash
tctl inventory ping <server-id>
```

---

## Resource Listing Commands

### `tctl apps ls` -- List Applications

```bash
tctl apps ls
tctl apps ls --format=json
tctl apps ls --verbose
tctl apps ls env=prod
tctl apps ls --search=grafana
tctl apps ls --query='labels["env"] == "prod"'
```

### `tctl db ls` -- List Databases

```bash
tctl db ls
tctl db ls --format=json
tctl db ls --verbose
tctl db ls env=staging
tctl db ls --search=postgres
tctl db ls --query='labels["engine"] == "postgres"'
```

### `tctl kube ls` -- List Kubernetes Clusters

```bash
tctl kube ls
tctl kube ls --format=json
tctl kube ls --verbose
tctl kube ls env=prod
tctl kube ls --search=production
tctl kube ls --query='labels["region"] == "us-east-1"'
```

### `tctl desktop ls` -- List Windows Desktops

```bash
tctl desktop ls
tctl desktop ls --format=json
tctl desktop ls --verbose
```

### `tctl desktop bootstrap` -- Bootstrap Active Directory

```bash
# Generate PowerShell script
tctl desktop bootstrap
```

### `tctl proxy ls` -- List Proxies

```bash
tctl proxy ls
tctl proxy ls --format=json
tctl proxy ls --format=text
```

#### Common Resource Listing Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--format` | | Output format: text, json, yaml | `text` |
| `--verbose` | `-v` | Verbose table output | off |
| `--search` | | Comma-separated search keywords (not available for `desktop ls`) | |
| `--query` | | Predicate language query (not available for `desktop ls`) | |

---

## Recordings

### `tctl recordings ls` -- List Recordings

```bash
tctl recordings ls
tctl recordings ls --format=json
tctl recordings ls --last=24h
tctl recordings ls --from-utc=2024-01-01 --to-utc=2024-01-31
tctl recordings ls --limit=100
```

#### Key Recordings Ls Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--format` | Output format: text, json, yaml | `text` |
| `--from-utc` | Start of time range (YYYY-MM-DD) | 24 hours ago |
| `--to-utc` | End of time range (YYYY-MM-DD) | current time |
| `--limit` | Maximum recordings to show | `50` |
| `--last` | Duration into the past (e.g., 5h30m40s) | |

### `tctl recordings download` -- Download Recordings

```bash
tctl recordings download <session-id>
tctl recordings download <session-id> --output-dir=/tmp/recordings
```

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--output-dir` | `-o` | Directory to download to | current directory |

### `tctl recordings encryption` -- Manage Recording Encryption

```bash
# Rotate encryption keys
tctl recordings encryption rotate

# Check rotation status
tctl recordings encryption status
tctl recordings encryption status --format=json

# Complete an in-progress rotation
tctl recordings encryption complete-rotation

# Rollback an in-progress rotation
tctl recordings encryption rollback-rotation
```

---

## SSO Configuration

### `tctl sso configure github` -- Configure GitHub Auth

```bash
tctl sso configure github \
  --id=<client-id> \
  --secret=<client-secret> \
  --teams-to-roles=myorg,devs,access \
  --teams-to-roles=myorg,admins,admin

# With custom name and display
tctl sso configure github \
  --name=github-corp \
  --display="GitHub Corporate" \
  --id=<client-id> \
  --secret=<client-secret> \
  --teams-to-roles=myorg,team,role

# GitHub Enterprise
tctl sso configure github \
  --id=<client-id> \
  --secret=<client-secret> \
  --endpoint-url=https://github.company.com \
  --api-endpoint-url=https://github.company.com/api/v3 \
  --teams-to-roles=myorg,devs,access
```

#### Key SSO Configure GitHub Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--name` | `-n` | Connector name | `github` |
| `--teams-to-roles` | `-r` | Teams-to-roles mapping (repeatable, required) | |
| `--display` | | Connector display name | |
| `--id` | | GitHub app client ID (required) | |
| `--secret` | | GitHub app client secret (required) | |
| `--endpoint-url` | | GitHub instance endpoint URL | |
| `--api-endpoint-url` | | GitHub instance API endpoint URL | |
| `--redirect-url` | | Authorization callback URL | |
| `--ignore-missing-roles` | | Ignore missing roles | off |

### `tctl sso configure saml` -- Configure SAML Auth

```bash
# From entity descriptor file
tctl sso configure saml \
  --name=okta \
  --entity-descriptor=metadata.xml \
  --attributes-to-roles=groups,admins,admin \
  --attributes-to-roles=groups,devs,access

# With preset
tctl sso configure saml \
  --preset=okta \
  --entity-descriptor=https://idp.example.com/metadata \
  --attributes-to-roles=groups,admins,admin

# Manual configuration
tctl sso configure saml \
  --name=my-saml \
  --issuer=https://idp.example.com \
  --sso=https://idp.example.com/sso \
  --cert=idp-cert.pem \
  --attributes-to-roles=role,admin,admin
```

#### Key SSO Configure SAML Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--preset` | `-p` | Preset: okta, onelogin, ad, adfs |
| `--name` | `-n` | Connector name |
| `--entity-descriptor` | `-e` | Entity Descriptor (file, URL, or XML) |
| `--attributes-to-roles` | `-r` | Attribute-to-role mapping (repeatable, required) |
| `--display` | | Connector display name |
| `--allow-idp-initiated` | | Allow IdP-initiated SSO flow |
| `--issuer` | | IdP issuer |
| `--sso` | | IdP SSO service URL |
| `--cert` | | IdP certificate PEM file |
| `--acs` | | Assertion Consumer Service URL |
| `--provider` | | External IdP type: ping, adfs |
| `--signing-key-file` | | Request signing key file |
| `--signing-cert-file` | | Request certificate file |
| `--assertion-key-file` | | Assertion key file |
| `--assertion-cert-file` | | Assertion cert file |
| `--ignore-missing-roles` | | Ignore missing roles |

### `tctl sso configure oidc` -- Configure OIDC Auth

```bash
# Basic OIDC
tctl sso configure oidc \
  --name=my-oidc \
  --id=<client-id> \
  --secret=<client-secret> \
  --issuer-url=https://idp.example.com \
  --claims-to-roles=groups,admins,admin

# Google Workspace
tctl sso configure oidc \
  --preset=google \
  --google-id=<client-id> \
  --secret=<client-secret> \
  --google-acc-uri=service-account.json \
  --google-admin=admin@example.com \
  --claims-to-roles=groups,admins,admin

# GitLab
tctl sso configure oidc \
  --preset=gitlab \
  --id=<client-id> \
  --secret=<client-secret> \
  --claims-to-roles=groups,admins,admin

# With additional scopes
tctl sso configure oidc \
  --name=my-oidc \
  --id=<client-id> \
  --secret=<client-secret> \
  --issuer-url=https://idp.example.com \
  --scope=email --scope=groups \
  --claims-to-roles=groups,admins,admin
```

#### Key SSO Configure OIDC Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--preset` | `-p` | Preset: google, gitlab, okta |
| `--name` | `-n` | Connector name |
| `--claims-to-roles` | `-r` | Claim-to-roles mapping (repeatable, required) |
| `--display` | | Connector display name |
| `--id` | | OIDC app client ID |
| `--secret` | | OIDC app client secret (required) |
| `--issuer-url` | | Issuer URL |
| `--redirect-url` | | Authorization callback URL(s) |
| `--prompt` | | OIDC prompt: none, select_account, login, consent |
| `--scope` | | Additional scopes (repeatable) |
| `--acr` | | Authentication Context Class Reference |
| `--provider` | | External IdP type: ping, adfs, netiq, okta |
| `--google-acc-uri` | | Google: service account credentials URI |
| `--google-acc` | | Google: service account credentials string |
| `--google-admin` | | Google: admin email to impersonate |
| `--google-legacy` | | Google: legacy group filtering |
| `--google-id` | | Google: shorthand for --id |
| `--ignore-missing-roles` | | Ignore missing roles |

### `tctl sso test` -- Test SSO Flow

```bash
# Test from connector file
tctl sso test connector.yaml

# Test from stdin
cat connector.yaml | tctl sso test

# Suppress browser
tctl sso test --browser=none connector.yaml
```

### `tctl saml export` -- Export SAML Signing Key

```bash
tctl saml export my-saml-connector
```

---

## Plugins

### `tctl plugins install okta` -- Install Okta Plugin

```bash
tctl plugins install okta \
  --org=https://myorg.okta.com \
  --saml-connector=okta \
  --users-sync \
  --accesslist-sync \
  --owner=admin@example.com

# With app and group sync
tctl plugins install okta \
  --org=https://myorg.okta.com \
  --saml-connector=okta \
  --appgroup-sync \
  --group-filter="Engineering*" \
  --app-filter="Teleport*"

# With SCIM
tctl plugins install okta \
  --org=https://myorg.okta.com \
  --saml-connector=okta \
  --scim \
  --api-token=<token>
```

### `tctl plugins install entraid` -- Install Entra ID Plugin

```bash
tctl plugins install entraid \
  --default-owner=admin@example.com

# With group filters
tctl plugins install entraid \
  --default-owner=admin@example.com \
  --group-name="Engineering.*" \
  --exclude-group-name="Test.*"

# Manual setup
tctl plugins install entraid \
  --default-owner=admin@example.com \
  --manual-setup
```

### `tctl plugins install awsic` -- Install AWS Identity Center Plugin

```bash
tctl plugins install awsic \
  --access-list-default-owner=admin@example.com \
  --scim-url=https://scim.us-east-1.amazonaws.com/... \
  --scim-token=<token> \
  --instance-region=us-east-1 \
  --instance-arn=arn:aws:sso:::instance/ssoins-...
```

### `tctl plugins install scim` -- Install SCIM Plugin

```bash
tctl plugins install scim --connector=my-saml-connector
```

### `tctl plugins install github` -- Install GitHub Plugin

```bash
tctl plugins install github
tctl plugins install github --start-date=2024-01-01
```

### `tctl plugins install netiq` -- Install NetIQ Plugin

```bash
tctl plugins install netiq
tctl plugins install netiq --insecure-skip-verify
```

### `tctl plugins delete` -- Remove Plugin

```bash
tctl plugins delete okta
```

### `tctl plugins cleanup` -- Clean Up Plugin

```bash
# Dry run (default)
tctl plugins cleanup okta

# Actually clean up
tctl plugins cleanup okta --no-dry-run
```

### `tctl plugins edit awsic` -- Edit AWS IC Plugin

```bash
tctl plugins edit awsic --roles-sync-mode=NONE
tctl plugins edit awsic --plugin-name=my-awsic --roles-sync-mode=ALL
```

### `tctl plugins rotate awsic` -- Rotate AWS IC Token

```bash
tctl plugins rotate awsic <new-token>
tctl plugins rotate awsic <new-token> --plugin-name=my-awsic
tctl plugins rotate awsic <new-token> --no-validate-token
```

---

## Notifications

### `tctl notifications create` -- Create Notification

```bash
# Broadcast notification
tctl notifications create --title="Maintenance" --content="Scheduled maintenance tonight"

# Target specific user
tctl notifications create --title="Action Required" --content="Please update MFA" --user=alice

# Target specific roles
tctl notifications create --title="Policy Update" --content="New security policy" --roles=admin,editor

# Target users with ALL roles
tctl notifications create --title="Admin Notice" --content="Admin review needed" \
  --roles=admin,editor --require-all-roles

# Warning notification
tctl notifications create --title="Warning" --content="Certificate expiring" --warning

# Custom TTL and labels
tctl notifications create --title="Notice" --content="Info" --ttl=7d --labels=team=security
```

#### Key Notifications Create Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--title` | `-t` | Notification title (required) | |
| `--content` | | Notification content (required) | |
| `--user` | | Target a specific user | |
| `--roles` | | Target specific roles | |
| `--require-all-roles` | | Target users with ALL provided roles | off |
| `--warning` | | Set as warning notification | off |
| `--ttl` | | Duration until expiry | `30d` |
| `--labels` | | Labels to attach | |

### `tctl notifications ls` -- List Notifications

```bash
tctl notifications ls
tctl notifications ls --format=json
tctl notifications ls --user=alice
tctl notifications ls --all
tctl notifications ls --labels=team=security
```

### `tctl notifications rm` -- Remove Notification

```bash
tctl notifications rm <notification-id>
tctl notifications rm <notification-id> --user=alice
```

---

## Workload Identity

### `tctl workload-identity ls` -- List Workload Identities

```bash
tctl workload-identity ls
```

### `tctl workload-identity rm` -- Remove Workload Identity

```bash
tctl workload-identity rm my-workload
```

### `tctl workload-identity revocations` -- Manage Revocations

```bash
# Add a revocation
tctl workload-identity revocations add \
  --serial=1234567890 \
  --type=x509 \
  --reason="Key compromised"

# Add with custom expiry
tctl workload-identity revocations add \
  --serial=1234567890 \
  --type=x509 \
  --reason="Key compromised" \
  --expires-at=2024-12-31T23:59:59Z

# List revocations
tctl workload-identity revocations ls

# Remove a revocation
tctl workload-identity revocations rm --serial=1234567890 --type=x509

# Fetch signed CRL
tctl workload-identity revocations crl
tctl workload-identity revocations crl --out=/tmp/crl.pem
tctl workload-identity revocations crl --follow
```

#### Key Revocations Add Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--serial` | Serial number of certificate to revoke (required) | |
| `--type` | Type of credential to revoke: x509 (required) | |
| `--reason` | Reason for revocation (required) | |
| `--expires-at` | Revocation expiry (RFC3339) | 1 week from now |

### `tctl workload-identity x509-issuer-overrides` -- Manage Issuer Overrides

```bash
# Create issuer override from certificate chain
tctl workload-identity x509-issuer-overrides create fullchain.pem
tctl workload-identity x509-issuer-overrides create --force --name=my-override fullchain.pem

# Dry run
tctl workload-identity x509-issuer-overrides create --dry-run fullchain.pem

# Sign CSRs with SPIFFE X.509 CA keys
tctl workload-identity x509-issuer-overrides sign-csrs
tctl workload-identity x509-issuer-overrides sign-csrs --creation-mode=empty --force
```

---

## Access Lists (ACL)

### `tctl acl ls` -- List Access Lists

```bash
tctl acl ls
tctl acl ls --format=json
```

### `tctl acl get` -- Get Access List Details

```bash
tctl acl get my-access-list
tctl acl get my-access-list --format=json
```

### `tctl acl users add` -- Add User to Access List

```bash
tctl acl users add my-access-list alice
tctl acl users add my-access-list alice "2024-12-31" "Temporary access"

# Add a list as member
tctl acl users add my-access-list other-list --kind=list
```

### `tctl acl users rm` -- Remove User from Access List

```bash
tctl acl users rm my-access-list alice
```

### `tctl acl users ls` -- List Access List Members

```bash
tctl acl users ls my-access-list
tctl acl users ls my-access-list --format=json
```

---

## Audit

### Audit Queries

```bash
# Execute an ad-hoc query
tctl audit query exec "SELECT * FROM session_start WHERE time > now() - interval '24 hours'"

# Create a saved query
tctl audit query create --name=recent-sessions "SELECT * FROM session_start WHERE time > now() - interval '24 hours'"

# List saved queries
tctl audit query ls

# Get query details
tctl audit query get recent-sessions

# Remove a query
tctl audit query rm recent-sessions

# Print audit schema
tctl audit schema
```

### Audit Reports

```bash
# List available reports
tctl audit report ls

# Get report details
tctl audit report get my-report

# Run a report
tctl audit report run my-report

# Check report state
tctl audit report state my-report
```

---

## Login Rules

### `tctl login_rule test` -- Test Login Rules

```bash
# Test with traits file
tctl login_rule test traits.yaml

# Test with rule file
tctl login_rule test --resource-file=rule.yaml traits.yaml

# Test with multiple rule files
tctl login_rule test --resource-file=rule1.yaml --resource-file=rule2.yaml traits.yaml

# Load rules from cluster
tctl login_rule test --load-from-cluster traits.yaml

# Output as JSON
tctl login_rule test --format=json traits.yaml
```

#### Key Login Rule Test Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--resource-file` | Login rule resource file (YAML/JSON, repeatable) | |
| `--load-from-cluster` | Load existing login rules from cluster | off |
| `--format` | Output format: yaml, json | `yaml` |

---

## IDP (Identity Provider)

### `tctl idp saml test-attribute-mapping` -- Test SAML Attribute Mapping

```bash
tctl idp saml test-attribute-mapping --users=alice --sp=sp-config.yaml
tctl idp saml test-attribute-mapping --users=user-spec.yaml --sp=sp-config.yaml --format=json
```

#### Key IDP SAML Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--users` | `-u` | Username or file containing user spec (required) |
| `--sp` | | File containing service provider spec (required) |
| `--format` | | Output format: yaml, json |

---

## Terraform Integration

### `tctl terraform env` -- Set Up Terraform Environment

```bash
# Create temporary bot and export env vars
tctl terraform env

# Use eval to set env vars in current shell
eval $(tctl terraform env)

# Custom prefix and TTL
tctl terraform env --resource-prefix=my-tf- --bot-ttl=2h

# Use existing role
tctl terraform env --role=my-terraform-role
```

#### Key Terraform Env Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--resource-prefix` | Resource prefix for Terraform role and bots | `tctl-terraform-env-` |
| `--bot-ttl` | TTL of Bot resource | `1h` |
| `--role` | Role used by Terraform | `terraform-provider` |

---

## Auto Update

### Client Tools Auto Update

```bash
# Check status
tctl autoupdate client-tools status
tctl autoupdate client-tools status --format=json
tctl autoupdate client-tools status --proxy=proxy.example.com

# Enable/disable
tctl autoupdate client-tools enable
tctl autoupdate client-tools disable

# Set target version
tctl autoupdate client-tools target v18.7.0

# Clear target (defaults to proxy version)
tctl autoupdate client-tools target --clear
```

### Agent Auto Update

```bash
# Check agent update status
tctl autoupdate agents status

# Get agent report
tctl autoupdate agents report

# Start updates for specific groups
tctl autoupdate agents start-update canary
tctl autoupdate agents start-update canary production

# Force update (skip canaries/backpressure)
tctl autoupdate agents start-update --force production

# Mark groups as done
tctl autoupdate agents mark-done canary

# Rollback groups
tctl autoupdate agents rollback production
tctl autoupdate agents rollback  # rollback all started groups
```

---

## Scoped Auth

### `tctl scoped tokens` -- Manage Scoped Tokens

```bash
# Add scoped token
tctl scoped tokens add --type=node --scope=my-scope --assign-scope=resource-scope

# With custom options
tctl scoped tokens add --type=node \
  --name=my-token \
  --ttl=1h \
  --scope=my-scope \
  --assign-scope=resource-scope \
  --labels=env=prod \
  --ssh-labels=team=backend \
  --mode=single_use

# List scoped tokens
tctl scoped tokens ls
tctl scoped tokens ls --format=json --with-secrets

# Delete scoped token
tctl scoped tokens rm my-token

# Show scoped status
tctl scoped status
```

#### Key Scoped Tokens Add Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--type` | Token type(s) (required) | |
| `--name` | Override token name | |
| `--ttl` | Token expiration | `30m` |
| `--format` | Output format: text, json, yaml | |
| `--assign-scope` | Scope for resources provisioned by this token | |
| `--scope` | Scope assigned to the token itself | |
| `--mode` | Usage mode: unlimited (default), single_use | |
| `--labels` | Token labels | |
| `--ssh-labels` | Immutable SSH labels for provisioned resources | |

---

## Stable UNIX Users

### `tctl stable-unix-users ls` -- List Stable UNIX Users

```bash
tctl stable-unix-users ls
tctl stable-unix-users ls --format=json
```

---

## Bound Keypair

### `tctl bound-keypair request-rotation` -- Request Keypair Rotation

```bash
tctl bound-keypair request-rotation my-token
```

---

## Predicate Language Query Syntax

Used by `--query` flags across many commands:

```bash
# Equality
--query='labels["env"] == "prod"'

# Inequality
--query='labels["env"] != "dev"'

# Logical AND
--query='labels["env"] == "prod" && labels["team"] == "backend"'

# Logical OR
--query='labels["env"] == "staging" || labels["env"] == "dev"'

# Combined
--query='(labels["env"] == "prod" || labels["env"] == "staging") && labels["region"] == "us-east-1"'
```

---

## Troubleshooting

### Enable Debug Logging

```bash
tctl --debug status
tctl -d get roles
```

### Common Issues

**"access denied" when running tctl:**

- Ensure you have admin role access
- For remote connections, use `--auth-server` and `-i` with a valid identity
- Check if the identity file has expired
- Verify the user's role includes the necessary `rules` for the resource type

**"connection refused" to auth server:**

- Check if Teleport auth service is running: `systemctl status teleport`
- Verify the auth server address: default is `127.0.0.1:3025`
- For remote access, use the proxy address with port 443
- Ensure network connectivity and firewall rules allow the connection

**"token not found" when using join tokens:**

- List tokens: `tctl tokens ls`
- Tokens expire; check TTL and recreate if needed
- Verify the token type matches the joining service

**"resource already exists" on create:**

- Use `tctl create -f` to overwrite
- Or use `tctl edit` to modify in place

**CA rotation issues:**

- Check current rotation status: `tctl status`
- Use `--manual` mode for controlled step-by-step rotation
- Rollback if needed: `tctl auth rotate --manual --type=<type> --phase=rollback`
- Ensure grace period is sufficient for all clients to update

**Identity file not working for remote tctl:**

- Verify the file exists and is readable
- Check if the identity was generated recently (certificates expire)
- Ensure the user associated with the identity has admin privileges
- Use `--insecure` only for testing when TLS verification fails

---

## Integration Patterns

### tctl with tbot (CI/CD)

```bash
# In CI/CD pipeline: get identity via tbot, then use tctl
tbot start identity \
  --proxy-server=proxy.example.com:443 \
  --join-method=github \
  --token=ci-bot \
  --oneshot \
  --destination=file:///tmp/tbot-out

# Use tctl with the identity
tctl -i /tmp/tbot-out/identity --auth-server=proxy.example.com:443 status
tctl -i /tmp/tbot-out/identity --auth-server=proxy.example.com:443 get roles
```

### tctl with Terraform

```bash
# Quick setup: creates temporary bot and outputs env vars
eval $(tctl terraform env)

# Then run Terraform
terraform plan
terraform apply
```

### Creating Resources for tbot Deployments

```bash
# 1. Create role for the bot
cat <<EOF | tctl create -f
kind: role
version: v7
metadata:
  name: my-bot-role
spec:
  allow:
    kubernetes_labels:
      env: ["prod", "staging"]
    kubernetes_groups: ["system:masters"]
    kubernetes_resources:
      - kind: "*"
        namespace: "*"
        name: "*"
        verbs: ["*"]
EOF

# 2. Create the bot
tctl bots add my-bot --roles=my-bot-role

# 3. Create join token (for Kubernetes)
cat <<EOF | tctl create -f
kind: token
version: v2
metadata:
  name: my-bot-token
spec:
  roles: [Bot]
  bot_name: my-bot
  join_method: kubernetes
  kubernetes:
    type: in_cluster
    allow:
      - service_account: "tbot:tbot"
EOF
```

### Bulk Resource Management

```bash
# Export all roles
tctl get roles > all-roles.yaml

# Export specific resources
tctl get role/admin > admin-role.yaml
tctl get users --format=json > users.json

# Apply resources from file
tctl create -f roles.yaml

# Pipe between commands
tctl get role/template | sed 's/template/new-role/' | tctl create -f
```

### Lock Management Patterns

```bash
# Emergency: lock a compromised user
tctl lock --user=compromised-user --message="Account compromised" --ttl=0

# Scheduled maintenance: lock a role temporarily
tctl lock --role=admin --message="Maintenance window" --ttl=4h

# Lock bot instance (revoke machine credentials)
tctl lock --bot-instance-id=<uuid> --message="Decommissioned"

# View all locks
tctl get locks
tctl get locks --format=json

# Remove a lock
tctl rm lock/<lock-id>
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TELEPORT_CONFIG_FILE` | Path to tctl configuration file |
| `TELEPORT_AUTH_SERVER` | Auth/proxy server address |
| `TELEPORT_IDENTITY_FILE` | Path to identity file for remote connections |
