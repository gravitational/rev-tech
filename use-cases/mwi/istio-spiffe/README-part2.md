# Part 2 — Off-Cluster VM via mTLS/SPIFFE

A Docker container simulates a VM running outside the Kubernetes cluster. tbot on the VM obtains a SPIFFE SVID from Teleport; Envoy uses it in-memory via SDS to make mTLS requests to the Sock Shop `catalogue` service. The Istio sidecar on `catalogue` validates the SVID — same Teleport CA as Part 1 — and checks the `AuthorizationPolicy`. Access can be granted or revoked with a single `kubectl` command, no restarts.

**Interactive walkthrough:** [`demo-walkthrough-part2.ipynb`](demo-walkthrough-part2.ipynb)

**Requires [Part 1](README-part1.md) to be deployed and healthy first.**

## What This Demo Proves

- An off-cluster workload joins the same zero-trust identity fabric as in-mesh pods
- No credentials ever touch disk — the SVID lives only in Envoy's process memory (fetched via SDS)
- The Istio sidecar trusts the SVID because Teleport is the mesh CA (set up in Part 1)
- Live policy control: delete the `AuthorizationPolicy` → VM locked out instantly; re-apply → restored

## Additional Prerequisites

Beyond Part 1:
- `docker` and `docker compose` available on this machine

## Architecture

```
┌──────────────────────────────────────────┐
│  Docker container (simulated VM)          │
│                                          │
│  tbot ──► /run/teleport/workload.sock    │
│                    ▲                     │
│           Envoy (SDS) ──────────────┐   │
│           localhost:8080 (proxy)    │   │
└─────────────────────────────────────┼───┘
                                      │ mTLS (Teleport SPIFFE SVID)
                                      ▼
                         Kubernetes cluster
                         ┌──────────────────────────────┐
                         │  catalogue-external LB svc    │
                         │  → pod iptables intercept     │
                         │  → Istio sidecar port 15006   │
                         │    validates SVID             │
                         │    checks AuthorizationPolicy │
                         │  → catalogue app container    │
                         └──────────────────────────────┘
```

## Setup

### 1. Create VM Workload Identity resources in Teleport

```bash
# WorkloadIdentity: issues spiffe://<domain>/demo/vm-service
tctl create -f tbot/vm-workload-identity.yaml

# Bot role: grants least-privilege access to the vm-demo identity
tctl create -f tbot/vm-bot-role.yaml

# Bot + one-time join token (save the token output)
tctl bots add demo-vm-bot --roles=demo-vm-workload-identity --ttl=8h
```

The token is consumed on first tbot start; after that, Teleport issues a renewable machine certificate.

### 2. Expose the catalogue service externally

```bash
kubectl apply -f sockshop/catalogue-external-svc.yaml
kubectl get svc catalogue-external -n sock-shop   # wait for EXTERNAL-IP
```

This creates a `LoadBalancer` service so the VM container can reach `catalogue`. Traffic goes through the pod's iptables rules → Istio sidecar → `AuthorizationPolicy` check → app container.

### 3. Apply the VM AuthorizationPolicy

```bash
TRUST_DOMAIN=your-cluster.teleport.sh \
  envsubst '${TRUST_DOMAIN}' < sockshop/vm-catalogue-authz.yaml | kubectl apply -f -
```

This `ALLOW` policy permits the SPIFFE ID `spiffe://your-cluster/demo/vm-service` to reach `catalogue`. It is additive — `catalogue-allow-frontend` (from Part 1) remains in effect.

### 4. Write .env.vm

```bash
cat > .env.vm <<EOF
TELEPORT_PROXY=your-cluster.teleport.sh:443
BOT_TOKEN=<token from step 1>
TRUST_DOMAIN=your-cluster.teleport.sh
CATALOGUE_HOST=<EXTERNAL-IP from step 2>
CATALOGUE_PORT=80
EOF
```

### 5. Build and start the VM container

```bash
docker compose build demo-vm
docker compose up -d demo-vm
```

The container runs tbot (joins Teleport, opens the Workload API socket) and Envoy (forward proxy on `:8080`, fetches SVID via SDS, admin on `:9901`). Wait ~15s for tbot to authenticate.

Verify the socket is ready:
```bash
docker exec demo-vm ls -la /run/teleport/workload.sock
```

## Demo Talking Points

### No credentials on disk

```bash
docker exec demo-vm find / -name '*.crt' -o -name '*.pem' -o -name '*.key' 2>/dev/null \
  | grep -v /etc/ssl | grep -v /proc | grep -v /sys
# Expected: (nothing)
```

The SVID lives only in Envoy's process memory.

### SPIFFE SVID in Envoy memory

```bash
curl -s http://localhost:9901/certs | python3 -m json.tool | grep -A2 spiffe
```

```json
"uri": "spiffe://your-cluster/demo/vm-service"
```

Envoy fetched this via the SPIFFE Workload API gRPC SDS call — never a file write.

### Successful mTLS request

```bash
docker exec demo-vm curl -s http://localhost:8080/catalogue | python3 -m json.tool | head -20
# HTTP 200 — catalogue product list
```

### Live policy: deny

```bash
kubectl delete authorizationpolicy catalogue-allow-vm -n sock-shop
sleep 5
docker exec demo-vm curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/catalogue
# HTTP 503 — VM locked out, no restarts, no cert changes
```

### Live policy: restore

```bash
TRUST_DOMAIN=your-cluster.teleport.sh \
  envsubst '${TRUST_DOMAIN}' < sockshop/vm-catalogue-authz.yaml | kubectl apply -f -
sleep 5
docker exec demo-vm curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/catalogue
# HTTP 200 — access restored
```

## Key Files

| File | Purpose |
|------|---------|
| `tbot/vm-workload-identity.yaml` | WorkloadIdentity: SPIFFE ID template `/demo/vm-service` |
| `tbot/vm-bot-role.yaml` | Bot role granting access to `purpose: vm-demo` identities |
| `sockshop/catalogue-external-svc.yaml` | LoadBalancer service exposing `catalogue` externally |
| `sockshop/vm-catalogue-authz.yaml` | `AuthorizationPolicy` allowing the VM's SPIFFE ID |
| `vm/Dockerfile` | Container image: Ubuntu + tbot + Envoy |
| `vm/tbot-vm.yaml` | tbot config template (substituted at container start) |
| `vm/envoy.yaml` | Envoy config: SDS upstream, forward proxy, admin |
| `vm/entrypoint.sh` | Starts tbot, waits for socket, starts Envoy |
| `docker-compose.yml` | Defines the `demo-vm` service |

## How It Works

1. tbot starts in the container, joins Teleport using the one-time token
2. tbot opens the SPIFFE Workload API socket at `/run/teleport/workload.sock`
3. Envoy starts, connects to the socket via SDS, fetches the SVID: `spiffe://your-cluster/demo/vm-service`
4. `curl http://localhost:8080/catalogue` hits Envoy's forward proxy
5. Envoy opens an mTLS connection to `catalogue-external`'s LoadBalancer IP, presenting the SVID
6. The Istio sidecar on the `catalogue` pod validates the cert (Teleport CA, correct trust domain)
7. The `AuthorizationPolicy` check: `catalogue-allow-vm` matches → request forwarded to the app
8. Catalogue returns the product list → Envoy returns it to curl

The denial path (Step 7 without `catalogue-allow-vm`) surfaces as HTTP 503 because `deny-all` is enforced at the TCP layer before any HTTP decoding.

## Cleanup

```bash
# Stop the VM container
docker compose down

# Remove Kubernetes resources
kubectl delete svc catalogue-external -n sock-shop --ignore-not-found
kubectl delete authorizationpolicy catalogue-allow-vm -n sock-shop --ignore-not-found

# Remove Teleport resources
tctl bots rm demo-vm-bot
tctl rm workload_identity/demo-vm-service
tctl rm role/demo-vm-workload-identity

# Remove local secret file
rm -f .env.vm
```

Part 1 resources (Istio, tbot DaemonSet, Sock Shop) are left intact.

To tear down everything including Part 1:
```bash
./cleanup.sh
```
