# Teleport Event-Handler Kubernetes Deployment

> **⚠ Non-production example**
>
> This setup is intended as a working reference for integrating Teleport's audit
> event stream with Fluent Bit or Fluentd. It is **not hardened for production use**.
> Before deploying to a production environment, review and address the following:
>
> - **mTLS certificates** are self-signed and generated locally. Replace with certs
>   issued by your internal CA or a certificate manager (e.g. cert-manager).
> - **RBAC** grants the event-handler bot read access to all Teleport audit events.
>   Scope the role to only the event types your pipeline requires.
> - **Output is stdout** by default. Configure a real destination (OpenSearch,
>   Splunk, Loki, etc.) before forwarding production audit data.
> - **Fluent Bit runs as a DaemonSet** and collects all pod logs on each node, not
>   just Teleport events. Review the input config before deploying cluster-wide.
> - **Secrets** (`fluent-bit-tls`, `teleport-identity`) are stored as plain
>   Kubernetes Secrets. Consider encrypting them at rest or using an external
>   secrets manager (e.g. AWS Secrets Manager, Vault).
> - **Version pinning** — Teleport component versions in `config.sh` must match
>   your cluster version exactly. Mismatches will cause auth failures.

This repo gives you a single-command Kubernetes deployment that continuously
streams Teleport audit events into a log pipeline of your choice.

**What you get:**

- Every SSH session, `kubectl exec`, web login, database query, and other
  Teleport audit event forwarded in real time to Fluent Bit or Fluentd
- mTLS between the event-handler and the log collector — events are encrypted
  and both sides are authenticated
- [Machine ID (tbot)](https://goteleport.com/docs/machine-id/) managing the
  Teleport identity — short-lived certificates, auto-renewed, no static secrets
  committed to the cluster
- A configurable join method (`eks`, `gcp`, `aks`, `token`, `bound_keypair`) so
  tbot can authenticate to Teleport using your cloud provider's native workload
  identity rather than a long-lived secret
- A pluggable output — default is stdout, swap in OpenSearch, Splunk, Loki,
  Kafka, S3, or any other Fluent Bit / Fluentd destination without changing
  anything else in the pipeline
- A `delete.sh` that cleanly removes everything from both Kubernetes and the
  Teleport cluster when you're done

## Architecture

```
Teleport Auth/Proxy
       │
       │  gRPC (audit stream)
       ▼
teleport-plugin-event-handler  (Helm: teleport/teleport-plugin-event-handler)
  reads identity from ──► teleport-identity  (K8s Secret, written by tbot)
       │
       │  HTTPS POST + mTLS
       ▼
    fluent-bit pod  (Helm: fluent/fluent-bit)
      ├── haproxy sidecar  — mTLS :8888, rewrites 201→200
      └── fluent-bit       — HTTP input :8889 (localhost only)
       │
       ▼
  stdout / swap in your output plugin

tbot  (Helm: teleport/tbot)
  joins via Kubernetes ServiceAccount token
  continuously renews ──► teleport-identity Secret
```

## Prerequisites

- `kubectl` pointed at your cluster
- `helm` 3+
- `openssl` available locally
- `jq` (used to auto-detect `TELEPORT_VERSION` from `/webapi/ping`)
- `tctl` authenticated to your Teleport cluster

## Quick start

```bash
# 1. Edit the three lines that matter
vim config.sh   # TELEPORT_ADDRESS, JOIN_METHOD, OUTPUT_TYPE

# 2. Deploy everything
./scripts/deploy.sh
```

## config.sh reference

| Variable | Values | Description |
|----------|--------|-------------|
| `NAMESPACE` | string | Kubernetes namespace for all components |
| `BOT_NAME` | string | Machine ID bot name; also used for the role and join token (`tbot-<BOT_NAME>`) |
| `TELEPORT_ADDRESS` | `host:port` | Teleport Proxy or Auth address |
| `CLUSTER_NAME` | string | Output of `tctl status \| grep Cluster` |
| `TELEPORT_VERSION` | semver | Must match the same cluster major version or n-1  |
| `JOIN_METHOD` | `eks` `gcp` `aks` `kubernetes` `token` `bound_keypair` | OIDC JWKS (eks/gcp/aks), in-cluster (kubernetes), static auto-generated token (token), asymmetric keypair (bound_keypair — Teleport 15+) |
| `OUTPUT_TYPE` | `fluent-bit` `fluentd` `none` | Fluent Bit (+ HAProxy sidecar), Fluentd (native 200), or bring your own |
| `FLUENTD_URL` | URL | Required when `OUTPUT_TYPE=none` — your own endpoint |
| `FLUENTD_SESSION_URL` | URL | Required when `OUTPUT_TYPE=none` — session logs endpoint |

### 2. Generate mTLS certs, apply Fluent Bit manifests

```bash
kubectl apply -f k8s/namespace.yaml
./scripts/generate-certs.sh   # creates fluent-bit-tls Secret
kubectl apply -k k8s/
```

### 3. Install tbot via Helm

```bash
helm repo add teleport https://charts.releases.teleport.dev
helm upgrade --install tbot teleport/tbot \
  --namespace teleport-events \
  --version 18.8.2 \
  -f helm/tbot/values.yaml
```

tbot joins using the pod's ServiceAccount token, then continuously renews the
identity and writes it to the `teleport-identity` Kubernetes Secret.

### 4. Install event-handler via Helm

```bash
helm upgrade --install event-handler teleport/teleport-plugin-event-handler \
  --namespace teleport-events \
  --version 18.8.2 \
  -f helm/event-handler/values.yaml
```

### 5. Verify

```bash
kubectl get pods -n teleport-events

kubectl logs -n teleport-events -l app.kubernetes.io/name=tbot -f
kubectl logs -n teleport-events -l app.kubernetes.io/name=teleport-plugin-event-handler -f
kubectl logs -n teleport-events -l app=fluent-bit -f
```

## Confirming events are flowing

### 1. Check the event-handler is fetching from Teleport

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=teleport-plugin-event-handler -f
```

Look for lines like:
```
INFO  successful fetch and process of event chunks date:2026-05-30 chunks:474 idle:false
INFO  Event processing events_per_minute:12 date:2026-05-30
```

`events_per_minute:0` with `idle:false` means Teleport has events but sending is failing.  
`events_per_minute:0` with no error output is normal when the cluster is quiet — trigger a test event (see below).

### 2. Check events arriving at Fluent Bit

```bash
# Follow the fluent-bit container (not haproxy) — events appear here as JSON lines
kubectl logs -n <namespace> -l app.kubernetes.io/name=fluent-bit -c fluent-bit -f
```

Each forwarded audit event looks like:
```json
{"date":1748613600.123,"event":"user.login","user":"alice","success":true,"cluster_name":"example.teleport.sh",...}
```

The DaemonSet runs one pod per node; events appear on whichever pod handled the connection. To see all at once:
```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=fluent-bit -c fluent-bit --prefix -f
```

### 3. Check events arriving at Fluentd

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=fluentd -f
```

Fluentd's stdout output prints records as:
```
2026-05-30 14:00:00.000000000 +0000 teleport.events: {"event":"user.login","user":"alice",...}
```

### 4. Trigger a test event

If the cluster is idle, generate an event by logging in via the Teleport Web UI or CLI:

```bash
tsh login --proxy=<cluster-address> --user=<your-user>
```

Within a few seconds `user.login` should appear in the output logs. You can also check HAProxy is receiving connections:

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=fluent-bit -c haproxy -f
```

Successful connections look like:
```
<134>May 30 14:00:01 haproxy[1]: 10.0.0.5:51234 [30/May/2026:14:00:01.123] https_in fluent_bit/fluent_bit 0/0/1/2/3 200 47 - - ---- 1/1/0/0/0 0/0 "POST /teleport.events HTTP/1.1"
```

A `200` in that line confirms HAProxy received the event, rewrote the status code, and Fluent Bit accepted it.

### 5. End-to-end health check

```bash
NS=<namespace>
echo "--- pods ---"
kubectl get pods -n $NS

echo "--- event-handler ---"
kubectl logs -n $NS -l app.kubernetes.io/name=teleport-plugin-event-handler --since=5m \
  | grep -E "events_per_minute|chunks|ERROR|WARN"

echo "--- haproxy (connection log) ---"
kubectl logs -n $NS -l app.kubernetes.io/name=fluent-bit -c haproxy --since=5m \
  | grep -v "^$"

echo "--- fluent-bit events ---"
kubectl logs -n $NS -l app.kubernetes.io/name=fluent-bit -c fluent-bit --since=5m \
  | grep '"event"'
```

## Customising the Fluent Bit output

Edit [helm/fluent-bit/values.yaml](helm/fluent-bit/values.yaml) and replace the `config.outputs` block.

```ini
# OpenSearch / Elasticsearch
[OUTPUT]
    Name         opensearch
    Match        *
    Host         opensearch.example.com
    Port         9200
    Index        teleport-events

# Splunk HEC
[OUTPUT]
    Name         splunk
    Match        *
    Host         splunk.example.com
    Port         8088
    Splunk_Token <hec-token>

# Loki
[OUTPUT]
    Name         loki
    Match        *
    Host         loki.example.com
    Port         3100
    Labels       job=teleport
```

## Files

```
config.sh                      # ← edit this: cluster address, join method, output type
k8s/
├── namespace.yaml
├── kustomization.yaml
├── tbot-serviceaccount.yaml   # SA with automountServiceAccountToken: true
└── haproxy-configmap.yaml     # HAProxy config (201→200 rewrite + mTLS termination)
helm/
├── fluent-bit/
│   └── values.yaml            # fluent/fluent-bit chart — HTTP input + HAProxy sidecar
├── fluentd/
│   └── values.yaml            # fluent/fluentd chart — native HTTP 200, no proxy needed
├── tbot/
│   └── values.yaml            # teleport/tbot chart — static config (address via --set)
└── event-handler/
    └── values.yaml            # teleport/teleport-plugin-event-handler (address/url via --set)
scripts/
├── deploy.sh                        # Reads config.sh, deploys everything
├── delete.sh                        # Removes all K8s resources and Teleport bot/role/token
├── generate-certs.sh                # CA + server/client certs → fluent-bit-tls Secret
└── generate-teleport-resources.sh   # Emits role+bot+token YAML for the chosen join method
```

## Notes

- The Kubernetes join token in `teleport-resources.yaml` binds to the
  `tbot` ServiceAccount in the `teleport-events` namespace, which is what
  the `teleport/tbot` Helm chart creates by default.
- tbot writes the identity to the `teleport-identity` Secret. The event-handler
  chart mounts this secret via `teleport.identitySecretName`.
- The `fluent-bit-tls` Secret holds all five cert files. The event-handler uses
  `ca.crt`, `client.crt`, `client.key`. Fluent Bit uses `ca.crt`, `server.crt`,
  `server.key`. Rotate by re-running `generate-certs.sh` and restarting both.

## Version pinning

`TELEPORT_VERSION` in `config.sh` must match your cluster major version or n-1. The `tbot`
and `teleport-plugin-event-handler` Helm charts and the event-handler container
image are all pinned to this value.

Look up your cluster version from the `/webapi/ping` endpoint — no auth needed:

```bash
curl -s https://<your-proxy>/webapi/ping | jq -r .server_version
```

Example against the example.trial.teleport.sh cluster:

```bash
curl -s https://example.trial.teleport.sh/webapi/ping | jq -r .server_version
```
