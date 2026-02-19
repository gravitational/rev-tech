# tbot -- Teleport Machine & Workload Identity Agent

tbot issues and renews short-lived certificates so machines and workloads can access Teleport-protected resources. It supports SSH, database, Kubernetes, application, and SPIFFE workload identity outputs.

**Binary:** `tbot` (Teleport v18+)
**Image:** `public.ecr.aws/gravitational/tbot-distroless` (FIPS: `tbot-fips-distroless`)
**Documentation:** <https://goteleport.com/docs/reference/cli/tbot/>

---

## Quick Reference

### Generate a Configuration File

Use `tbot configure <output-type>` to generate YAML. All `configure` subcommands mirror `start` subcommands. All accept `-o, --output=PATH` to write to a file (defaults to stdout).

Available configure subcommands: `identity`, `database`, `kubernetes`, `kubernetes/v2`, `application`, `database-tunnel`, `application-tunnel`, `application-proxy`, `ssh-multiplexer`, `workload-identity-x509`, `workload-identity-jwt`, `workload-identity-aws-roles-anywhere`, `workload-identity-api`, `noop`, `legacy`.

```bash
# Generate identity output config
tbot configure identity \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=my-bot \
  --destination=file:///opt/machine-id/identity \
  -o /etc/tbot.yaml

# Generate kubernetes output config
tbot configure kubernetes \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=my-bot \
  --destination=file:///opt/machine-id/k8s \
  --kubernetes-cluster=my-cluster \
  -o /etc/tbot.yaml

# Generate database tunnel config
tbot configure database-tunnel \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=my-bot \
  --listen=tcp://127.0.0.1:5432 \
  --service=my-postgres --username=reader --database=mydb \
  -o /etc/tbot.yaml

# Generate SPIFFE X.509 SVID config
tbot configure workload-identity-x509 \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=my-bot \
  --destination=file:///opt/machine-id/svid \
  --name-selector=my-workload \
  -o /etc/tbot.yaml
```

### Start tbot Directly (CLI flags)

Available start subcommands: `identity` (aliases: `ssh`, `id`), `database` (alias: `db`), `kubernetes` (alias: `k8s`), `kubernetes/v2` (alias: `k8s/v2`), `application` (alias: `app`), `database-tunnel` (alias: `db-tunnel`), `application-tunnel` (alias: `app-tunnel`), `application-proxy` (alias: `app-proxy`), `ssh-multiplexer`, `workload-identity-x509`, `workload-identity-jwt`, `workload-identity-aws-roles-anywhere`, `workload-identity-api`, `noop` (alias: `no-op`), `legacy`.

```bash
# Identity output
tbot start identity \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=my-bot \
  --destination=file:///opt/machine-id/identity \
  --allow-reissue

# Database output
tbot start database \
  --proxy-server=example.teleport.sh:443 \
  --join-method=token \
  --token=db-bot \
  --destination=file:///opt/machine-id/db \
  --service=my-postgres --username=reader --database=mydb \
  --format=tls   # tls (default) | mongo | cockroach

# Kubernetes output (single cluster)
tbot start kubernetes \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=k8s-bot \
  --destination=file:///opt/machine-id/k8s \
  --kubernetes-cluster=my-cluster \
  --disable-exec-plugin   # use static creds without tbot binary

# Kubernetes output (multi-cluster)
tbot start kubernetes/v2 \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=k8s-bot \
  --destination=file:///opt/machine-id/k8s \
  --name-selector=my-cluster \
  --label-selector=env=production   # repeatable

# Application output
tbot start application \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=app-bot \
  --destination=file:///opt/machine-id/app \
  --app=grafana \
  --specific-tls-extensions

# Database tunnel
tbot start database-tunnel \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=db-bot \
  --listen=tcp://127.0.0.1:5432 \
  --service=my-postgres --username=reader --database=mydb

# Application tunnel
tbot start application-tunnel \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=app-bot \
  --listen=tcp://127.0.0.1:8080 \
  --app=grafana

# Application proxy
tbot start application-proxy \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=app-bot \
  --listen=tcp://0.0.0.0:8080

# SSH multiplexer
tbot start ssh-multiplexer \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=ssh-bot \
  --destination=file:///opt/machine-id/ssh-mux \
  --enable-resumption \
  --proxy-command=fdpass-teleport \
  --proxy-templates-path=/etc/tbot/proxy-templates.yaml

# SPIFFE X.509 SVID output
tbot start workload-identity-x509 \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=wi-bot \
  --destination=file:///opt/machine-id/svid \
  --name-selector=my-workload \
  --include-federated-trust-bundles

# SPIFFE X.509 SVID output (with label selector -- mutually exclusive with --name-selector)
tbot start workload-identity-x509 \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=wi-bot \
  --destination=file:///opt/machine-id/svid \
  --label-selector=team=backend

# SPIFFE JWT SVID output
tbot start workload-identity-jwt \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=wi-bot \
  --destination=file:///opt/machine-id/jwt \
  --name-selector=my-workload \
  --audience=https://my-service.example.com   # required, repeatable

# AWS Roles Anywhere output
tbot start workload-identity-aws-roles-anywhere \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=wi-bot \
  --destination=file:///opt/machine-id/aws \
  --name-selector=my-workload \
  --role-arn=arn:aws:iam::123456789012:role/my-role \
  --profile-arn=arn:aws:rolesanywhere:us-east-1:123456789012:profile/PROFILE_ID \
  --trust-anchor-arn=arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/ANCHOR_ID \
  --region=us-east-1 \
  --session-duration=6h \
  --session-renewal-interval=1h

# SPIFFE Workload API (unix socket)
tbot start workload-identity-api \
  --proxy-server=example.teleport.sh:443 \
  --join-method=kubernetes \
  --token=wi-bot \
  --listen=unix:///run/tbot/workload.sock \
  --name-selector=my-workload

# Legacy mode (v1 compatibility)
tbot start legacy \
  --proxy-server=example.teleport.sh:443 \
  --join-method=token \
  --token=my-bot \
  --data-dir=/var/lib/teleport/bot \
  --destination-dir=/opt/machine-id
```

### Start with Config File

```bash
tbot start -c /etc/tbot.yaml
```

---

## Configuration File Reference (v2)

### Minimal Config

```yaml
version: v2
proxy_server: "example.teleport.sh:443"
onboarding:
  token: "my-bot"
  join_method: kubernetes
storage:
  type: memory
services:
  - type: identity
    destination:
      type: directory
      path: /opt/machine-id/identity
```

> **Note:** The config reference marks `outputs` as a legacy field. Use `services` for all output and service types. Both arrays still work, but `services` is the recommended approach.

### Full Config Structure

```yaml
version: v2
debug: false
proxy_server: "example.teleport.sh:443"   # or auth_server for direct auth
credential_ttl: "1h"                       # max 24h
renewal_interval: "20m"                    # must be < credential_ttl
oneshot: false                             # true for CI/CD (exit after first renewal)

onboarding:
  token: "token-name"        # token name or /path/to/file
  join_method: "kubernetes"  # see Join Methods section
  ca_pins:
    - "sha256:..."           # pin Auth Server CA (first connect only)
  ca_path: "/path/to/ca.pem" # alternative to ca_pins
  # For GitLab join:
  # gitlab:
  #   token_env_var_name: "CUSTOM_ID_TOKEN"  # custom env var for GitLab ID token
  # For bound_keypair join:
  # bound_keypair:
  #   registration_secret: "secret"
  #   registration_secret_path: "/path/to/secret"
  #   static_key_path: "/path/to/key"

storage:
  type: memory               # memory | directory | kubernetes_secret
  # For directory:
  # type: directory
  # path: /var/lib/teleport/bot
  # For kubernetes_secret:
  # type: kubernetes_secret
  # name: tbot-storage

outputs: []    # legacy; use services instead
services: []   # all output and service types (see below)
```

---

## Output Types

All output types support these optional per-output fields:

- `roles` -- list of roles for certificate generation (overrides default)
- `credential_ttl` -- per-output TTL override
- `renewal_interval` -- per-output renewal interval override
- `name` -- custom service identifier

### Quick Reference

| Output Type | Writes Files | Listens on Socket | Use Case |
|-------------|:---:|:---:|------------|
| identity | Yes | No | SSH access, Teleport API |
| database | Yes | No | Database credential files |
| kubernetes | Yes | No | Kubeconfig for single cluster |
| kubernetes/v2 | Yes | No | Kubeconfig for multiple clusters (selectors) |
| application | Yes | No | App TLS credential files |
| application-tunnel | No | Yes | Local TCP tunnel to Teleport app |
| database-tunnel | No | Yes | Local TCP tunnel to Teleport database |
| workload-identity-x509 | Yes | No | SPIFFE X.509 SVIDs |
| workload-identity-api | No | Yes | SPIFFE Workload API / Envoy SDS |
| workload-identity-jwt | Yes | No | SPIFFE JWT SVIDs |
| workload-identity-aws-roles-anywhere | Yes | No | AWS credentials via Roles Anywhere |
| application-proxy | No | Yes | HTTP proxy to Teleport app |
| ssh-multiplexer | Yes | No | SSH multiplexer with ProxyCommand |

### identity -- SSH and Teleport API Access

```yaml
services:
  - type: identity
    destination:
      type: directory             # or kubernetes_secret
      path: /opt/machine-id/identity
    # Optional:
    cluster: leaf-cluster         # issue for a specific leaf cluster
    # allow_reissue: false        # allow credentials to be reissued
    # ssh_config: "on"            # on | off
    # roles: [access]
    # credential_ttl: "1h"
    # renewal_interval: "20m"
```

Files produced: `identity`, `tls.crt`, `tls.key`, `tls.cas`, `ssh_config`, `known_hosts`, etc.

### database -- Database Credentials

```yaml
services:
  - type: database
    service: my-postgres          # database service name in Teleport
    username: reader              # database user
    database: mydb                # database name
    # format: tls                 # tls (default) | mongo | cockroach
    destination:
      type: directory
      path: /opt/machine-id/db
```

### kubernetes -- Single Cluster Kubeconfig

```yaml
services:
  - type: kubernetes
    kubernetes_cluster: my-cluster   # cluster name in Teleport
    # disable_exec_plugin: false     # set true to use static creds without tbot binary
    destination:
      type: directory
      path: /opt/machine-id/k8s
```

### kubernetes/v2 -- Multi-Cluster Kubeconfig

```yaml
services:
  - type: kubernetes/v2
    selectors:                        # plural, array of selectors
      - name: specific-cluster
        default_namespace: my-namespace
      - labels:
          env: production
    # disable_exec_plugin: false
    # context_name_template: "{{.ClusterName}}-{{.KubeName}}"
    # relay_server: relay.example.com:443
    destination:
      type: directory
      path: /opt/machine-id/k8s
```

### kubernetes/argo-cd -- Argo CD Cluster Discovery

```yaml
services:
  - type: kubernetes/argo-cd
    selectors:
      - name: my-cluster
      - labels:
          env: staging
    secret_namespace: argocd
    secret_name_prefix: tbot-
    # secret_labels: {}
    # secret_annotations: {}
    # project: default
    # namespaces: ["ns1", "ns2"]
    # cluster_resources: true
    # cluster_name_template: "{{.ClusterName}}"
```

### ssh_host -- OpenSSH Server Integration

```yaml
services:
  - type: ssh_host
    principals:
      - host1.example.com
      - host2.example.com
    destination:
      type: directory
      path: /opt/machine-id/ssh-host
```

Produces host certificates and CA exports for OpenSSH server integration.

### application -- Application TLS Credentials

```yaml
services:
  - type: application
    app_name: grafana
    destination:
      type: directory
      path: /opt/machine-id/app
```

### workload-identity-x509 -- SPIFFE X.509 SVID

```yaml
services:
  - type: workload-identity-x509
    selector:
      name: my-workload           # by name
      # or labels: { team: backend }
    # include_federated_trust_bundles: false
    destination:
      type: directory
      path: /opt/machine-id/svid
```

Files produced: `svid.pem`, `svid_key.pem`, `bundle.pem`

### workload-identity-jwt -- SPIFFE JWT SVID

```yaml
services:
  - type: workload-identity-jwt
    selector:
      name: my-workload
    audiences:
      - "https://my-service.example.com"
    destination:
      type: directory
      path: /opt/machine-id/jwt
```

#### JWT SVID Claims and OIDC Compatibility

Key JWT claims: `sub` (SPIFFE ID), `aud` (intended recipients), `exp` (default 5min expiration), `iat` (issuance time), `jti` (unique ID for audit), `iss` (issuer from Proxy public config).

JWT SVIDs are OIDC-compatible. Teleport exposes `/.well-known/openid-configuration` and `/jwt-jwks.json` for verification. Tested cloud integrations: AWS OIDC Federation, GCP Workload Identity Federation, Azure Federated Credentials.

### workload-identity-aws-roles-anywhere -- AWS Credentials via X.509 SVID

```yaml
services:
  - type: workload-identity-aws-roles-anywhere
    selector:
      name: my-workload
    role_arn: "arn:aws:iam::123456789012:role/my-role"
    profile_arn: "arn:aws:rolesanywhere:us-east-1:123456789012:profile/PROFILE_ID"
    trust_anchor_arn: "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/ANCHOR_ID"
    # region: us-east-1
    # session_duration: "6h"
    # session_renewal_interval: "1h"
    # credential_profile_name: custom-profile
    # artifact_name: aws_credentials         # custom filename (default: aws_credentials)
    # overwrite_credential_file: false
    destination:
      type: directory
      path: /opt/machine-id/aws
```

---

## Service Types

### workload-identity-api -- SPIFFE Workload API + Envoy SDS

```yaml
services:
  - type: workload-identity-api
    listen: unix:///run/tbot/workload.sock   # or tcp://0.0.0.0:8443
    selector:
      name: my-workload
    # attestors:
    #   unix:                          # default, reads procfs
    #     binary_hash_max_size_bytes: 1073741824
    #   kubernetes:                    # requires DaemonSet + hostPID
    #     kubelet:
    #       read_only_port: 10255
    #       secure_port: 10250
    #       token_path: /var/run/secrets/kubernetes.io/serviceaccount/token
    #       ca_path: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    #       skip_verify: false
    #       anonymous: false
    #   docker: {}                     # queries Docker Engine API socket
    #   podman: {}                     # queries Podman API socket (rootful/rootless)
    #   systemd: {}                    # restricts to specific systemd services via D-Bus
    #   sigstore:                      # validates signed container images
    #     additional_registries: []
    #     credentials_path: ""
    #     allowed_private_network_prefixes: []
```

Workloads set `SPIFFE_ENDPOINT_SOCKET` and use any SPIFFE SDK.
Also implements Envoy SDS (secrets: `default`, `ROOTCA`, `ALL`).

#### Envoy SDS Configuration

```yaml
# Envoy cluster using SDS for mTLS via tbot Workload API
clusters:
  - name: backend
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        common_tls_context:
          tls_certificate_sds_secret_configs:
            - name: "default"
              sds_config:
                api_config_source:
                  api_type: GRPC
                  grpc_services:
                    - google_grpc:
                        target_uri: "unix:///run/tbot/workload.sock"
          validation_context_sds_secret_config:
            name: "ROOTCA"
            sds_config:
              api_config_source:
                api_type: GRPC
                grpc_services:
                  - google_grpc:
                      target_uri: "unix:///run/tbot/workload.sock"
```

Use cases: forward proxy (attach SVID to outgoing connections), reverse proxy (validate client mTLS), service mesh (full mTLS with automatic rotation).

Unix attestor: reads procfs, captures executable path and SHA-256 checksums. Set `HOST_PROC` env var for non-standard procfs mount.

### application-tunnel -- Local Tunnel to App

```yaml
services:
  - type: application-tunnel
    listen: tcp://127.0.0.1:8080   # also supports unix:///path/to/socket
    app_name: grafana
```

### database-tunnel -- Local Tunnel to Database

```yaml
services:
  - type: database-tunnel
    listen: tcp://127.0.0.1:5432   # also supports unix:///path/to/socket
    service: my-postgres
    database: mydb
    username: reader
```

### application-proxy -- HTTP Reverse Proxy

```yaml
services:
  - type: application-proxy
    listen: tcp://0.0.0.0:8080     # also supports unix:///path/to/socket
```

Limitations: HTTP/1.x only; HTTP/2 and TCP applications are not supported.

### ssh-multiplexer -- SSH Connection Multiplexer

```yaml
services:
  - type: ssh-multiplexer
    destination:
      type: directory
      path: /opt/machine-id/ssh-mux
    # enable_resumption: true      # SSH session resumption
    # proxy_command: ["fdpass-teleport"]  # custom ProxyCommand
    # proxy_templates_path: /etc/tbot/proxy-templates.yaml
    # relay_server: relay.example.com:443
```

Artifacts produced: `ssh_config`, `known_hosts`, `v1.sock`, `agent.sock`

---

## Deprecated Types

- `spiffe-svid` output type: replaced by `workload-identity-x509` and `workload-identity-jwt`
- `spiffe-workload-api` service type: replaced by `workload-identity-api`

---

## Destination Types

```yaml
# File-based
destination:
  type: directory
  path: /opt/machine-id/output
  symlinks: try-secure   # try-secure (default) | secure | insecure
  acls: try              # try (default) | off | required
  readers:               # structured reader list (alternative to CLI --reader-user/--reader-group)
    - user: "teleport"   # or user: 123 (UID)
    - group: "teleport"  # or group: 456 (GID)

# Kubernetes Secret
destination:
  type: kubernetes_secret
  name: tbot-output
  # namespace: default   # defaults to tbot's namespace

# In-memory (services only, not for file outputs)
destination:
  type: memory
```

---

## Kubernetes Deployment

### Deployment Patterns

| Pattern | When to Use |
|---------|-------------|
| **Standalone Deployment** (recommended) | Writes credentials to a Kubernetes Secret; other pods mount the Secret. Best for most use cases. |
| **Sidecar** | tbot runs in the same pod. Use when credentials go to a shared emptyDir, when workloads need the SPIFFE Workload API via Unix socket, or when workload attestation requires co-location. |
| **DaemonSet** | Required for Workload Identity API with Kubernetes attestation. Runs with `hostPID: true`, exposes SPIFFE socket per node, queries local kubelet for workload identity. Requires ClusterRole for pods/nodes/nodes-proxy. |

### Helm Chart (Recommended)

```bash
helm repo add teleport https://charts.releases.teleport.dev
helm repo update
helm install tbot teleport/tbot \
  --namespace tbot --create-namespace \
  --values tbot-values.yaml
```

### Helm Values for Identity Output

```yaml
clusterName: "example.teleport.sh"
teleportProxyAddress: "example.teleport.sh:443"
token: "my-bot"
joinMethod: "kubernetes"       # default
defaultOutput:
  enabled: true                # creates identity output to Secret "tbot-out"
```

### Helm Values for Kubernetes Cluster Access

```yaml
clusterName: "example.teleport.sh"
teleportProxyAddress: "example.teleport.sh:443"
token: "k8s-bot"
defaultOutput:
  enabled: false
outputs:
  - type: kubernetes
    kubernetes_cluster: target-cluster
    destination:
      type: kubernetes_secret
      name: tbot-k8s-creds
```

### Helm Values for Workload Identity API

```yaml
clusterName: "example.teleport.sh"
teleportProxyAddress: "example.teleport.sh:443"
token: "wi-bot"
defaultOutput:
  enabled: false
services:
  - type: workload-identity-api
    listen: unix:///run/tbot/workload.sock
    selector:
      name: my-workload
```

### Helm Values for Argo CD Integration

```yaml
clusterName: "example.teleport.sh"
teleportProxyAddress: "example.teleport.sh:443"
token: "argocd-bot"
defaultOutput:
  enabled: false
argocd:
  enabled: true
  clusterSelectors:
    - labels:
        env: production
  secretNamespace: argocd
  secretNamePrefix: tbot-
  # secretLabels: {}
  # secretAnnotations: {}
  # project: default
  # namespaces: []
  # clusterResources: true
  # clusterNameTemplate: "{{.ClusterName}}"
```

### Helm Values for Multiple Outputs

```yaml
clusterName: "example.teleport.sh"
teleportProxyAddress: "example.teleport.sh:443"
token: "multi-bot"
defaultOutput:
  enabled: false
outputs:
  - type: identity
    destination:
      type: kubernetes_secret
      name: tbot-identity
  - type: database
    service: my-postgres
    username: app
    database: appdb
    destination:
      type: kubernetes_secret
      name: tbot-db-creds
  - type: kubernetes
    kubernetes_cluster: staging
    destination:
      type: kubernetes_secret
      name: tbot-k8s-staging
```

### Key Helm Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `clusterName` | `""` | Teleport cluster name |
| `teleportProxyAddress` | `""` | Proxy address (host:port) |
| `teleportAuthAddress` | `""` | Auth Service address (alternative to proxy) |
| `token` | `""` | Join token name |
| `joinMethod` | `"kubernetes"` | Join method |
| `defaultOutput.enabled` | `true` | Enable default identity output |
| `outputs` | `[]` | Additional output configs |
| `services` | `[]` | Service configs |
| `argocd.enabled` | `false` | Enable Argo CD integration |
| `persistence` | `"secret"` | Storage: "secret" or "disabled" |
| `serviceAccount.create` | `true` | Create ServiceAccount |
| `rbac.create` | `true` | Create Role/RoleBinding |
| `image` | `public.ecr.aws/gravitational/tbot-distroless` | Container image |
| `imagePullPolicy` | `"IfNotPresent"` | Image pull policy |
| `imagePullSecrets` | `[]` | Image pull secrets |
| `resources` | `{}` | CPU/memory requests/limits |
| `tbotConfig` | `{}` | Full custom tbot YAML (overrides chart) |
| `extraVolumes` | `[]` | Additional volumes |
| `extraVolumeMounts` | `[]` | Additional volume mounts |
| `extraArgs` | `[]` | Additional tbot CLI args |
| `extraEnv` | `[]` | Additional environment variables |
| `debug` | `false` | Enable debug logging |
| `anonymousTelemetry` | `false` | Enable usage telemetry |
| `teleportVersionOverride` | `""` | Override image version (dev only) |
| `affinity` | `{}` | Pod affinity rules |
| `tolerations` | `[]` | Node taints tolerance |
| `nodeSelector` | `{}` | Node selection constraints |
| `securityContext` | `{}` | Container security settings |
| `podSecurityContext` | `{}` | Pod-level security settings |
| `extraLabels.*` | `{}` | Labels for resources (Role, RoleBinding, ConfigMap, Deployment, Pod, ServiceAccount) |
| `annotations.*` | `{}` | Annotations for various resources |

### Consuming tbot Credentials in Other Pods

```yaml
# In a Deployment spec
containers:
  - name: app
    env:
      - name: KUBECONFIG
        value: /tbot-k8s/kubeconfig.yaml
    volumeMounts:
      - name: k8s-creds
        mountPath: /tbot-k8s
        readOnly: true
volumes:
  - name: k8s-creds
    secret:
      secretName: tbot-k8s-creds
```

### DaemonSet for Workload Attestation

When using the workload-identity-api with Kubernetes attestation, tbot must run as a DaemonSet with `hostPID: true`. This lets tbot query the local Kubelet API to identify which pod is requesting credentials. Requires RBAC for pods, nodes, and node proxy access.

---

## Join Methods

### Kubernetes (Recommended for K8s)

Three variants based on how the SA token is validated:

**in_cluster** -- Uses Kubernetes TokenReview API. Requires network access from Teleport Auth to the K8s API.

```yaml
kind: token
version: v2
metadata:
  name: my-bot
spec:
  roles: [Bot]
  bot_name: my-bot
  join_method: kubernetes
  kubernetes:
    type: in_cluster
    allow:
      - service_account: "NAMESPACE:SERVICE_ACCOUNT"
```

**static_jwks** -- Validates SA JWT signatures using exported JWKS. Works when K8s API is not reachable from Teleport.

```yaml
kind: token
version: v2
metadata:
  name: my-bot
spec:
  roles: [Bot]
  bot_name: my-bot
  join_method: kubernetes
  kubernetes:
    type: static_jwks
    static_jwks:
      jwks: |
        {"keys":[...]}
    allow:
      - service_account: "NAMESPACE:SERVICE_ACCOUNT"
```

Export JWKS: `kubectl get --raw /openid/v1/jwks`

**oidc** -- Uses publicly accessible OIDC issuer. Best for EKS, GKE, AKS.

```yaml
kind: token
version: v2
metadata:
  name: my-bot
spec:
  roles: [Bot]
  bot_name: my-bot
  join_method: kubernetes
  kubernetes:
    type: oidc
    oidc:
      issuer: https://oidc.eks.us-west-2.amazonaws.com/id/CLUSTER_ID
    allow:
      - service_account: "NAMESPACE:SERVICE_ACCOUNT"
```

### Token (Simple, Ephemeral)

```yaml
kind: token
version: v2
metadata:
  name: my-token
spec:
  roles: [Bot]
  bot_name: my-bot
  join_method: token
```

Or via CLI: `tctl tokens add --type=bot --bot-name=my-bot --ttl=30m`

### IAM (AWS)

```yaml
kind: token
version: v2
metadata:
  name: iam-bot
spec:
  roles: [Bot]
  bot_name: my-bot
  join_method: iam
  allow:
    - aws_account: "111111111111"
      aws_arn: "arn:aws:sts::111111111111:assumed-role/role-name/*"
```

### Other Methods

| Method | Use Case |
|--------|----------|
| `gcp` | GCP VMs with service accounts |
| `azure` | Azure VMs with managed identity |
| `github` | GitHub Actions OIDC |
| `gitlab` | GitLab CI OIDC |
| `circleci` | CircleCI OIDC |
| `spacelift` | Spacelift runs |
| `terraform_cloud` | Terraform Cloud runs |
| `azure_devops` | Azure DevOps pipelines |
| `bitbucket` | Bitbucket Pipelines OIDC |
| `oracle` | Oracle Cloud Infrastructure |
| `env0` | env0 environment runs |
| `tpm` | Hardware TPM attestation (on-premises) |
| `bound_keypair` | Pre-registered keypair |

### Join Method Properties

| Method | Renewable | Secret-free |
|--------|-----------|-------------|
| token | Yes | No (ephemeral secret) |
| kubernetes | No | Yes |
| iam | No | Yes |
| tpm | No | Yes |
| gcp/azure | No | Yes |
| github/gitlab/circleci | No | Yes |
| azure_devops/bitbucket | No | Yes |
| spacelift/terraform_cloud | No | Yes |
| oracle/env0 | No | Yes |
| bound_keypair | Yes | Yes (pre-registered key) |

Non-renewable methods re-join on each renewal cycle. Prefer secret-free methods in production.

---

## SPIFFE Workload Identity Setup

### Step-by-Step

**1. Create a WorkloadIdentity resource in Teleport:**

```yaml
kind: workload_identity
version: v1
metadata:
  name: my-service
  labels:
    team: backend
spec:
  spiffe:
    id: /svc/my-service
```

Apply: `tctl create -f workload-identity.yaml`

**2. Create an RBAC role for issuing the identity:**

```yaml
kind: role
version: v6
metadata:
  name: wi-issuer
spec:
  allow:
    workload_identity_labels:
      team: ["backend"]           # or "*": ["*"] for all
    rules:
      - resources: [workload_identity]
        verbs: [list, read]
```

Apply: `tctl create -f role.yaml`

**3. Create a bot with the role:**

```yaml
kind: bot
version: v1
metadata:
  name: wi-bot
spec:
  roles:
    - wi-issuer
```

Apply: `tctl create -f bot.yaml`
Or CLI: `tctl bots add wi-bot --roles=wi-issuer`

**4. Create a join token:**

```yaml
kind: token
version: v2
metadata:
  name: wi-bot-token
spec:
  roles: [Bot]
  bot_name: wi-bot
  join_method: kubernetes
  kubernetes:
    type: in_cluster
    allow:
      - service_account: "default:tbot"
```

Apply: `tctl create -f token.yaml`

**5. Deploy tbot with workload-identity-x509 output:**

```yaml
version: v2
proxy_server: "example.teleport.sh:443"
onboarding:
  token: "wi-bot-token"
  join_method: kubernetes
storage:
  type: memory
services:
  - type: workload-identity-x509
    selector:
      name: my-service
    destination:
      type: directory
      path: /opt/svid
```

Or use workload-identity-api for the SPIFFE Workload API:

```yaml
services:
  - type: workload-identity-api
    listen: unix:///run/tbot/workload.sock
    selector:
      name: my-service
```

**6. In workloads, consume via SPIFFE SDK:**

```bash
export SPIFFE_ENDPOINT_SOCKET=unix:///run/tbot/workload.sock
```

### SPIFFE ID Structuring

Three approaches for organizing SPIFFE IDs:

- **Logical** (recommended): By workload function -- `spiffe://example.teleport.sh/production/payments/processor`. Enables access rules based on service groups.
- **Physical**: By infrastructure location -- `spiffe://example.teleport.sh/europe/uk/london/hypervisor-001/vm-a3847f`. Useful for proximity-based access controls.
- **Hybrid**: Multiple SVIDs per workload with prefixed namespacing (`phy/` for physical, `svc/` for service). Avoids collisions.

Avoid placing sensitive information in SPIFFE IDs since they are exposed to connecting workloads.

### Inspect a Running Workload API

```bash
tbot spiffe-inspect --path=unix:///run/tbot/workload.sock
```

---

## Bot Management with tctl

```bash
# Create a bot
tctl bots add my-bot --roles=access,wi-issuer

# List bots
tctl bots ls

# Update bot roles
tctl bots update my-bot --add-roles new-role
tctl bots update my-bot --set-roles role1,role2

# Remove a bot
tctl bots rm my-bot

# Create a join token
tctl tokens add --type=bot --bot-name=my-bot --ttl=30m

# List tokens
tctl tokens ls
```

---

## Utility Commands

```bash
# Show help
tbot help [<command>...]

# Initialize destination directory with proper permissions
tbot init \
  --destination-dir=/opt/machine-id \
  --bot-user=tbot \
  --reader-user=app \
  --owner=tbot:tbot \
  --clean \
  --init-dir=/opt/machine-id/identity   # specific destination from config

# Wait for tbot to become ready (all services)
tbot wait --diag-addr=127.0.0.1:3025 --timeout=30s

# Wait for a specific service to become ready
tbot wait --diag-addr=127.0.0.1:3025 --service=my-service --timeout=30s

# Print tbot version
tbot version

# Inspect SPIFFE Workload API
tbot spiffe-inspect --path=unix:///run/tbot/workload.sock

# Install systemd unit
tbot install systemd \
  -c /etc/tbot.yaml \
  --write \
  --user=teleport \
  --group=teleport \
  --name=tbot \
  --systemd-directory=/etc/systemd/system \
  --force \
  --anonymous-telemetry \
  --pid-file=/run/tbot.pid

# Migrate old config to v2
tbot migrate -c /etc/tbot-old.yaml -o /etc/tbot.yaml

# Copy tbot binary for exec plugin use
tbot copy-binaries /usr/local/bin

# Copy tbot + fdpass-teleport binaries
tbot copy-binaries --include-fdpass /usr/local/bin

# Identify TPM (for tpm join method)
tbot tpm identify

# Create keypair for bound-keypair joining
tbot keypair create --proxy-server=example.teleport.sh:443 --storage=file:///var/lib/teleport/bot
# Create a static keypair (prints key to terminal or writes to file)
tbot keypair create --proxy-server=example.teleport.sh:443 --static --static-key-path=/path/to/key
# Overwrite existing keypair; output as JSON
tbot keypair create --proxy-server=example.teleport.sh:443 --storage=file:///var/lib/teleport/bot --overwrite --format=json

# Proxy through tbot credentials (wraps tsh proxy)
tbot proxy --proxy-server=example.teleport.sh:443 --destination-dir=/opt/machine-id/identity --cluster=leaf-cluster -- ssh myhost

# Database commands through tbot credentials (wraps tsh db)
tbot db --proxy-server=example.teleport.sh:443 --destination-dir=/opt/machine-id/db --cluster=leaf-cluster -- connect mydb
```

---

## Troubleshooting

### Enable Debug Logging

```bash
tbot start -c /etc/tbot.yaml --debug
# or set TBOT_DEBUG=1
# or in config: debug: true
```

### Common Issues

**"token not found" or "access denied" on join:**

- Verify the token exists: `tctl tokens ls`
- Check `bot_name` in token matches the bot name
- For kubernetes join: verify ServiceAccount matches the `allow` rules (`NAMESPACE:SA_NAME`)
- For in_cluster type: ensure Teleport Auth can reach the K8s API server

**"certificate has expired":**

- tbot renewal may have failed; check logs
- Ensure `renewal_interval` < `credential_ttl`
- For non-renewable join methods, tbot must be able to re-join

**Kubernetes credentials not working:**

- Verify the bot has a role granting `kubernetes_labels` matching the target cluster
- Check cluster name matches exactly: `tctl get kube_cluster`

**Workload identity SVIDs empty or not issued:**

- Verify WorkloadIdentity resource exists: `tctl get workload_identity`
- Verify bot role has `workload_identity_labels` matching the resource
- Verify the selector in tbot config matches the resource name or labels

**Permission denied on destination directory:**

- Run `tbot init` to set up proper ownership and ACLs
- Ensure the tbot user can write to the directory
- For Kubernetes Secret destinations, ensure RBAC allows Secret create/update

**Helm chart: pod in CrashLoopBackOff:**

- Check logs: `kubectl logs deployment/tbot`
- Verify `clusterName` and `teleportProxyAddress` are correct
- Verify the join token exists and allows the ServiceAccount
- Check network connectivity to the Teleport proxy

### Diagnostic Endpoint

Run tbot with `--diag-addr=0.0.0.0:3025` and check:

- `http://localhost:3025/healthz` -- health check
- `http://localhost:3025/readyz` -- readiness check
- `http://localhost:3025/livez` -- liveness check

Use with Kubernetes probes:

```yaml
# In Helm values or pod spec
livenessProbe:
  httpGet:
    path: /livez
    port: 3025
readinessProbe:
  httpGet:
    path: /readyz
    port: 3025
```

---

## Global Flags

| Flag | Description |
|------|-------------|
| `-d`, `--debug` | Verbose logging |
| `-c`, `--config=PATH` | Config file path |
| `--fips` | FIPS compliance mode |
| `--insecure` | Skip TLS verification (never in production) |
| `--log-format=text` | Log format: `text` or `json` |

---

## Common Start/Configure Flags

These flags are shared across all `start` and `configure` subcommands (the `legacy` subcommand supports only `--auth-server`, `--proxy-server`, `--token`, `--ca-pin`, `--join-method`, `--certificate-ttl`, `--renewal-interval`, `--oneshot`, `--diag-addr`, `--pid-file`, `--data-dir`, `--destination-dir`):

| Flag | Description |
|------|-------------|
| `-a`, `--auth-server` | Auth Server address (prefer `--proxy-server`) |
| `--proxy-server` | Proxy Server address |
| `--token` | Bot join token or path to token file |
| `--ca-pin` | CA pin for Auth Server validation (repeatable) |
| `--join-method` | Cluster join method |
| `--join-uri` | URI with joining/auth parameters (alternative to individual flags) |
| `--storage` | Internal storage destination URI |
| `--certificate-ttl` | TTL of short-lived certificates |
| `--renewal-interval` | Certificate renewal interval (must be < TTL) |
| `--oneshot` | Exit after first renewal (for CI/CD) |
| `--diag-addr` | Diagnostics service listen address (debug mode) |
| `--pid-file` | Path to PID file |
| `--destination` | Output destination URI (file-output commands) |
| `--reader-user` | Additional ACL reader user (Linux, repeatable) |
| `--reader-group` | Additional ACL reader group (Linux, repeatable) |
| `--registration-secret` | Registration secret for bound keypair join |
| `--registration-secret-path` | File containing bound keypair registration secret |
| `--static-key-path` | Path to static key for bound keypair join |

---

## Environment Variables

| Variable | Maps to |
|----------|---------|
| `TBOT_DEBUG` | `--debug` |
| `TBOT_CONFIG_PATH` | `--config` |
| `TELEPORT_AUTH_SERVER` | `--auth-server` |
| `TELEPORT_PROXY` | `--proxy-server` |
| `TELEPORT_BOT_TOKEN` | `--token` |
| `SPIFFE_ENDPOINT_SOCKET` | Consumed by SPIFFE SDKs to find the Workload API |
