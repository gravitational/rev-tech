# Part 1 — In-Cluster mTLS with Teleport SPIFFE Identities

Teleport replaces Istio's built-in CA (Citadel). Every pod in the mesh gets a SPIFFE certificate issued by Teleport. `AuthorizationPolicy` rules reference SPIFFE IDs to control service-to-service access — zero-trust, cryptographically enforced.

**Interactive walkthrough:** [`demo-walkthrough.ipynb`](demo-walkthrough.ipynb)

## What This Demo Proves

- Teleport issues SPIFFE SVIDs to Istio sidecars instead of Citadel
- Every `service-to-service` call is encrypted and mutually authenticated using Teleport certs
- `AuthorizationPolicy` rules define which SPIFFE IDs (callers) can reach which services
- Deny-all → targeted allow: zero-trust in practice

## Prerequisites

- `kubectl` (1.27+), `istioctl` (1.28+), `tctl`, `tsh`
- Kubernetes cluster admin access
- Teleport cluster admin access (`tsh login` completed)

```bash
kubectl cluster-info
istioctl version
tctl status
```

## Setup

### 1. Configure the Teleport trust domain

```bash
cp .env.example .env
# Edit .env and set TELEPORT_TRUST_DOMAIN=your-cluster.teleport.sh
./configure-trust-domain.sh
```

This patches `istio/istio-config.yaml`, `tbot/tbot-config.yaml`, `tbot/tbot-daemonset.yaml`, and `sockshop/sock-shop-policies.yaml` in one shot.

### 2. Install Istio with SPIFFE integration

```bash
./istio-install.sh
kubectl get pods -n istio-system
```

Key config: Istio uses the `tbot-socket` injection template so every sidecar mounts the tbot Unix socket (`/run/spire/sockets/socket`) as a hostPath. pilot-agent auto-detects the socket and switches from the Citadel CA client to the SPIFFE Workload API.

### 3. Create Teleport resources

```bash
# Extract cluster JWKS and generate the join token file
./create-token.sh

# Create the join token (contains cluster-specific JWKS — gitignored)
tctl create -f istio/istio-tbot-token.yaml

# Bot role (least-privilege: can only issue SVIDs for istio-workloads)
tctl create -f tbot/teleport-bot-role.yaml

# WorkloadIdentity template: /ns/{{ namespace }}/sa/{{ service_account }}
tctl create -f tbot/teleport-workload-identity.yaml
```

Verify:
```bash
tctl get token/istio-tbot-k8s-join
tctl get role/istio-workload-identity-issuer
tctl get workload_identity/istio-workloads
```

### 4. Deploy tbot

```bash
kubectl apply -f tbot/tbot-rbac.yaml
kubectl apply -f tbot/tbot-config.yaml
kubectl apply -f tbot/tbot-daemonset.yaml
```

tbot runs as a DaemonSet — one pod per node — because Istio sidecars reach the Workload API via a Unix socket on the local node filesystem, not over the network. Verify it opened the socket:

```bash
kubectl logs -n teleport-system -l app=tbot --tail=20 | grep "Workload API"
```

### 5. Deploy Sock Shop

```bash
kubectl apply -f sockshop/sock-shop-demo.yaml
kubectl get pods -n sock-shop -w   # wait for all pods to show 2/2
```

`2/2` means the app container + Istio sidecar are both running. The sidecar has already fetched a SPIFFE SVID from tbot.

### 6. Verify SPIFFE identities

```bash
./validate-spiffe-ids.sh    # confirms each sidecar holds a Teleport-issued cert
./teleport-cert-demo.sh     # decodes the certificate and shows issuer/SAN
```

Expected:
```
=== Service: front-end ===
Expected: spiffe://your-cluster/ns/sock-shop/sa/front-end
Actual:   spiffe://your-cluster/ns/sock-shop/sa/front-end
✅ SPIFFE ID matches!
```

### 7. Test without policies (baseline)

```bash
FRONTEND_IP=$(kubectl get svc -n sock-shop front-end -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$FRONTEND_IP/catalogue   # expect HTTP 200
```

mTLS is active but no authorization policies exist yet — all authenticated services can talk freely.

### 8. Apply zero-trust policies

```bash
# Deny everything
kubectl apply -f sockshop/sock-shop-deny-all.yaml
curl http://$FRONTEND_IP/catalogue   # expect HTTP 403

# Allow only the right SPIFFE IDs on the right paths
kubectl apply -f sockshop/sock-shop-policies.yaml
curl http://$FRONTEND_IP/catalogue   # expect HTTP 200
```

### 9. Verify mTLS enforcement

```bash
# Check Envoy stats — non-zero mutual_tls counter confirms encrypted, authenticated traffic
POD=$(kubectl get pod -n sock-shop -l app=catalogue -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n sock-shop $POD -c istio-proxy -- \
  curl -s localhost:15000/stats | grep "connection_security_policy.mutual_tls"
```

```bash
# Unauthorized pod — no matching ALLOW policy → connection refused
kubectl run test-curl -n sock-shop --image=curlimages/curl:latest --restart=Never -- \
  sh -c "curl -v http://catalogue/catalogue 2>&1; sleep 10"
kubectl logs test-curl -n sock-shop
kubectl delete pod test-curl -n sock-shop
```

## How It Works

1. **tbot DaemonSet** runs on each node, opens the SPIFFE Workload API socket at `/run/spire/sockets/socket`
2. **Istio sidecar** (pilot-agent) detects the socket and uses the Workload API instead of Citadel
3. **Teleport issues certs** with SANs like `spiffe://your-cluster/ns/sock-shop/sa/front-end`
4. **Istio enforces mTLS** using those certs for every sidecar-to-sidecar call
5. **`AuthorizationPolicy`** rules reference the SPIFFE ID to grant or deny access

## Key Files

| File | Purpose |
|------|---------|
| `istio/istio-config.yaml` | Istio mesh config: trust domain, `tbot-socket` injection template |
| `istio-install.sh` | Installs Istio using the config above |
| `tbot/tbot-rbac.yaml` | ServiceAccount + ClusterRole for tbot |
| `tbot/tbot-config.yaml` | tbot configuration (proxy server, workload identity output) |
| `tbot/tbot-daemonset.yaml` | DaemonSet deployment |
| `tbot/teleport-bot-role.yaml` | Bot role (least-privilege SVID issuance) |
| `tbot/teleport-workload-identity.yaml` | SPIFFE ID template |
| `istio/istio-tbot-token.yaml.template` | Join token template (cluster JWKS required) |
| `sockshop/sock-shop-demo.yaml` | Sock Shop microservices app |
| `sockshop/sock-shop-deny-all.yaml` | Empty-spec deny-all `AuthorizationPolicy` |
| `sockshop/sock-shop-policies.yaml` | SPIFFE-based allow policies + PeerAuthentication |
| `validate-spiffe-ids.sh` | Verify SPIFFE IDs on live sidecars |
| `teleport-cert-demo.sh` | Decode and display a Teleport-issued certificate |

## Important Notes

- `istio/istio-tbot-token.yaml` (generated by `create-token.sh`) contains cluster-specific JWKS — **never commit it**
- SPIFFE IDs must include `/sa/`: `/ns/<namespace>/sa/<service-account>`
- Istio path normalization must be `NONE` to avoid SPIFFE ID matching issues in `AuthorizationPolicy`
- Socket path `/run/spire/sockets/socket` is the standard SPIFFE Workload API location

## Cleanup

```bash
./cleanup.sh
```

Removes Istio (`istio-system`), tbot (`teleport-system`), Sock Shop (`sock-shop`), and all Teleport resources.

---

**Continue to [Part 2 — Off-Cluster VM via mTLS](README-part2.md)** to extend the same identity fabric to a workload running outside the cluster.
