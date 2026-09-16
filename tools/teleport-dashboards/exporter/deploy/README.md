# Deploying the Teleport usage exporter

The exporter reads the Teleport API and serves Prometheus metrics. It works on
**any edition and any audit backend**, because it asks the API rather than
reading a datastore.

Nothing here is licence-restricted: the binary links only
`github.com/gravitational/teleport/api`, which is Apache 2.0, and no Enterprise
code. Enterprise *features* (Access Graph, Access Lists) affect which collectors
have data to report, not whether the exporter runs.

---

## The one real constraint: match the Teleport version

**Build the exporter against the same Teleport minor release as the cluster it
watches, and tag the image with that exact version.**

Teleport adds new resource kinds in **minor** releases. A binary built against
18.7 pointed at an 18.9 cluster will not error — it will simply not know about
whatever 18.9 added, count what it does know, and publish the shortfall as fact.
An under-count presented confidently is the exact failure this exporter was
built to eliminate, so it is worth being fussy about.

The exporter checks this itself at startup:

```
teleport_usage_version_mismatch 0    # client and server minors agree
teleport_usage_version_mismatch 1    # they do not — counts may be low
```

It logs a warning and **keeps running**. Refusing to start would take monitoring
down exactly when a cluster is mid-upgrade, which is when it is most wanted.
`scripts/corroborations.json` asserts the metric is 0, so skew surfaces as a
validation failure rather than a log line nobody reads.

Rebuild for a different cluster version:

```bash
make build-for TELEPORT_VERSION=v18.9.0   # repins teleport/api, then builds
```

**Tag images with the exact version and never `:latest`.** A floating tag makes
skew invisible; an exact tag makes a stale deployment obvious in `kubectl get
pods -o wide`. Concretely: `ghcr.io/<org>/teleport-usage-exporter:18.8.0`.

---

## Build it yourself

You do not need a registry to try this. The exporter is a single static binary in
a thin Alpine image, so you can build it, run it locally, and load it straight
into a cluster's container runtime.

### 1. Binaries

```bash
cd tools/teleport-usage
for arch in amd64 arm64; do
  CGO_ENABLED=0 GOOS=linux GOARCH=$arch go build \
    -ldflags "-s -w -X main.buildVersion=$(git rev-parse --short HEAD)" \
    -o teleport-usage-linux-$arch ./cmd/teleport-usage
done
```

Roughly 49 MB each. Both are gitignored.

### 2. Image

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t teleport-usage-exporter:18.8.0 .
```

**Always pass `--platform` explicitly.** `docker build` defaults to the *host*
architecture, so building on an Apple-silicon laptop produces an arm64 image
that an amd64 cluster will happily accept and then kill with
`exec format error`. That turns a build-time mistake into a deploy-time
surprise. Check before you ship it:

```bash
docker image inspect teleport-usage-exporter:18.8.0 --format '{{.Architecture}}'
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}'
```

### 3. Try it without a cluster

The fastest way to see the design working is to point it somewhere unreachable:

```bash
docker run --rm -p 8080:8080 teleport-usage-exporter:18.8.0 \
  exporter --proxy 127.0.0.1:1

curl -s localhost:8080/healthz   # 200 — the process is fine
curl -s localhost:8080/readyz    # 503 — nothing has collected yet
curl -s localhost:8080/metrics | grep teleport_usage_
```

`/metrics` will carry `collector_up 0` and **no `protected_resources` series at
all**. That absence is the point: a collector that cannot measure something
withdraws its metrics rather than publishing a zero, because a zero is
indistinguishable from a real measurement of zero.

Against a real cluster, with an identity file exported by `tbot` or
`tctl auth sign`:

```bash
docker run --rm -p 8080:8080 -v "$PWD/identity:/id:ro" \
  teleport-usage-exporter:18.8.0 \
  exporter --proxy teleport.example.com:443 --identity-file /id
```

### 4. Load it into a cluster without a registry

Useful for testing before you decide to publish anything.

```bash
docker save teleport-usage-exporter:18.8.0 -o /tmp/exporter.tar   # ~18 MB

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$NODE --image=alpine:3.20 --profile=sysadmin -q -- sleep 900 &
sleep 10
POD=$(kubectl get pods --no-headers | grep "node-debugger-$NODE" | awk '{print $1}')

kubectl cp /tmp/exporter.tar "$POD:/host/tmp/exporter.tar"
kubectl exec "$POD" -- chroot /host /usr/bin/ctr -n k8s.io images import /tmp/exporter.tar
kubectl exec "$POD" -- rm -f /host/tmp/exporter.tar
kubectl delete pod "$POD"
```

Deploy it with `imagePullPolicy: IfNotPresent` and no `imagePullSecrets`, and
the node uses the imported image. Repeat per node on a multi-node cluster — this
is a testing shortcut, not a distribution mechanism.

### 5. Publish

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u <user> --password-stdin
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/<org>/teleport-usage-exporter:18.8.0 \
  -t ghcr.io/<org>/teleport-usage-exporter:18.8.0-$(git rev-parse --short HEAD) \
  --push .
```

The token needs **`write:packages`**. `docker login` succeeds with only `repo`
scope and then fails at push time with
`denied: permission_denied: The token provided does not match expected scopes`,
which is a confusing place to discover it.

GHCR packages are **private by default**, so a cluster pulling one needs an
`imagePullSecret`:

```bash
kubectl -n teleport create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io --docker-username=<user> --docker-password="$GITHUB_TOKEN"
```

Verify what you published, from the registry rather than from local state:

```bash
docker buildx imagetools inspect ghcr.io/<org>/teleport-usage-exporter:18.8.0
```

## Kubernetes

Two manifests. `tbot.yaml` maintains the identity; `exporter.yaml` runs the
exporter.

```bash
export TELEPORT_DOMAIN=teleport.example.com
export USAGE_EXPORTER_IMAGE=ghcr.io/<org>/teleport-usage-exporter:18.8.0
# Name of a docker-registry Secret. GHCR packages are private by default; if
# yours is public, delete the imagePullSecrets block from exporter.yaml instead.
export USAGE_EXPORTER_PULL_SECRET=ghcr-pull-secret

# Match your cluster's EDITION and major version:
export TELEPORT_TBOT_IMAGE=public.ecr.aws/gravitational/teleport-distroless:18       # OSS
# export TELEPORT_TBOT_IMAGE=public.ecr.aws/gravitational/teleport-ent-distroless:18 # Enterprise

envsubst < deploy/kubernetes/tbot.yaml     | kubectl apply -f -
envsubst < deploy/kubernetes/exporter.yaml | kubectl apply -f -
```

First apply the Teleport-side resources (role, bot, join token) from
`teleport/roles/role-usage-exporter.yaml`, `teleport/bots/` and
`teleport/tokens/` — tbot cannot join without them.

### Identity rotation works without a restart

tbot writes the identity into a Secret; kubelet updates the mounted file in
place; the exporter hashes that file every 30s and rebuilds its Teleport client
when the hash moves. No restart, no Reloader dependency.

The Deployment does carry a Stakater Reloader annotation, but only as a second
line of defence — VM and Docker deployments have no Reloader, and rotation has
to work there too. The predecessor to this exporter relied on a restart it never
received and authenticated with a dead certificate for 68 days.

### Probes

`/healthz` is liveness and stays green while collectors fail. Restarting cannot
fix a Teleport outage, and a crash-loop would destroy the `collector_up` signal
explaining what is wrong.

`/readyz` is "has this exporter ever produced data" and is 503 until the first
successful collection, so a pod that can never authenticate never goes Ready
instead of going Ready while serving an empty `/metrics`.

---

## Verifying a deployment

```bash
kubectl -n teleport port-forward svc/teleport-usage-exporter 8080:8080 &
curl -s localhost:8080/metrics | grep teleport_usage_
```

Check, in order:

| Metric | Expect |
|---|---|
| `teleport_usage_collector_up{...}` | `1` for every collector |
| `teleport_usage_version_mismatch` | `0` |
| `teleport_usage_protected_resources_total` | equal to `tctl inventory status` |
| `teleport_usage_build_info` | correct cluster name and API version |

**If a metric is missing rather than zero, that is the design working.** A
collector that cannot measure something withdraws its series so Prometheus
records staleness and the panel reads "No data". A zero would be
indistinguishable from a real measurement of zero, which is how the previous
collector hid a month-long outage.

Cross-check against an independent source:

```bash
./scripts/validate-dashboards.py --prom http://localhost:9090
```

The `C1` corroborations compare the exporter against
`teleport_connected_resources` and assert the collectors are up, fresh, and
version-matched.

---

## Other environments

| Environment | Identity | Notes |
|---|---|---|
| Kubernetes | tbot, `kubernetes` join | above |
| EC2 / VM | tbot, `iam` join → file | systemd unit — Phase 3b |
| Docker | mounted identity file | compose — Phase 3b |

Configuration precedence is flag → env → default, so a container needs no flags:

| Flag | Env | Default |
|---|---|---|
| `--proxy` | `TELEPORT_USAGE_PROXY` | *(required)* |
| `--identity-file` | `TELEPORT_USAGE_IDENTITY_FILE` | ambient `tsh` profile |
| `--metrics-addr` | `TELEPORT_USAGE_METRICS_ADDR` | `:8080` |
| `--ping-timeout` | `TELEPORT_USAGE_PING_TIMEOUT` | `30s` |
