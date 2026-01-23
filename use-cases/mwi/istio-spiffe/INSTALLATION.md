# Installation Guide: Istio + Teleport Workload Identity

This guide provides step-by-step instructions for setting up Teleport Workload Identity integration with Istio on a clean Kubernetes cluster.

## Prerequisites

### Required Tools
- `kubectl` (1.27+)
- `istioctl` (1.28+)
- `tctl` (Teleport admin tool)
- `tsh` (Teleport client)

### Required Access
- Kubernetes cluster admin access
- Teleport cluster admin access
- Authenticated `tsh` session (`tsh login`)

### Verify Prerequisites

```bash
# Check Kubernetes access
kubectl cluster-info

# Check istioctl installation
istioctl version

# Check Teleport authentication
tctl status
```

## Installation Steps

### Step 1: Set Your Kubeconfig (if needed)

If you're using a non-default kubeconfig:

```bash
export KUBECONFIG=/path/to/your/kubeconfig.yaml
kubectl config current-context
```

### Step 2: Install Istio with SPIFFE Integration

Run the automated installation script:

```bash
./istio-install.sh
```

This script will:
- Create the `istio-system` namespace
- Install Istio with SPIFFE configuration
- Configure trust domain as `ellinj.teleport.sh` (must match your Teleport cluster domain)
- Disable path normalization for SPIFFE compatibility
- Deploy istiod and istio-ingressgateway

**Verify Istio installation:**

```bash
kubectl get pods -n istio-system
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
istio-ingressgateway-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
istiod-xxxxxxxxxx-xxxxx                 1/1     Running   0          1m
```

### Step 3: Extract Cluster JWKS

**CRITICAL STEP**: Every Kubernetes cluster has unique JWKS (JSON Web Key Set) used to validate service account tokens. You must extract your cluster's JWKS for Teleport authentication.

```bash
kubectl get --raw /openid/v1/jwks
```

**Example output:**
```json
{"keys":[{"use":"sig","kty":"RSA","kid":"lgRxZ4gmqOUOvCYs4UvaGe_mGsU_xFP60CtzEgT3BFU","alg":"RS256","n":"yjDQbEkltgSNEAZattubid7Uo5fWKrcgoJ3ZQSfWa9_9cLberxef8p0qC4Ss6atMfPMWI5N1_b59LG5ulnXFB0jGl5yjpn20bUOr_7In3-1caBp8yGD9bMPaZ8VAdKhMAAJXnXZTsW33URKiM8C53GE4DmYZJ6neksNCzbQqV8s1g7E96xVE0tmAJu4ZlWksIIRkbNvCx4oZNFcsl4W15jfFuBD2J5DT92UiG_xj-B9Z60ckT_AxND0cRud9aqrsep5YqaW5mGNG3mpt6460oEqWKgrteI8WvdheIZySxpaJOmvnh3kcLK6CxYfByNYbDmmjoCTqzLQ9CyclmJ3ckw","e":"AQAB"}]}
```

**Copy this entire JSON output** - you'll need it in the next step.

### Step 4: Create Kubernetes Join Token with Cluster JWKS

**SECURITY NOTE**: The token file contains cluster-specific JWKS and should NEVER be committed to version control. A template file is provided, and the actual token file is already in `.gitignore`.

**Option A: Use the automated helper script (recommended):**

```bash
./create-token.sh
```

This script will automatically extract the cluster JWKS and create `istio-tbot-token.yaml` from the template.

**Option B: Manual creation:**

```bash
# Copy the template
cp istio-tbot-token.yaml.template istio-tbot-token.yaml

# Extract JWKS and update the token file
kubectl get --raw /openid/v1/jwks | \
  sed 's/"/\\"/g' | \
  xargs -I {} sed -i.bak "s|'PASTE_JWKS_HERE'|'{}'|" istio-tbot-token.yaml

# Clean up backup file (macOS creates .bak files)
rm -f istio-tbot-token.yaml.bak
```

**The file `istio-tbot-token.yaml` is gitignored and should remain local only.**

**Create the token in Teleport:**

```bash
tctl create -f istio-tbot-token.yaml
```

**Verify token creation:**

```bash
tctl get token/istio-tbot-k8s-join
```

### Step 5: Create Teleport Bot Role

This role grants the bot permission to issue workload identities.

```bash
tctl create -f teleport-bot-role.yaml
```

**Verify role creation:**

```bash
tctl get role/istio-workload-identity-issuer
```

### Step 6: Create Workload Identity Resource

This defines the SPIFFE ID template for Kubernetes workloads.

**IMPORTANT**: The SPIFFE ID template must match Istio's expected format with `/sa/`:
```
spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>
```

```bash
tctl create -f teleport-workload-identity.yaml
```

**Verify workload identity:**

```bash
tctl get workload_identity/istio-workloads
```

The template should show:
```yaml
spec:
  spiffe:
    id: /ns/{{ workload.kubernetes.namespace }}/sa/{{ workload.kubernetes.service_account }}
```

Note the `/sa/` component is critical for Istio compatibility.

### Step 7: Deploy tbot to Kubernetes

Deploy the tbot DaemonSet that will provide the SPIFFE Workload API on each node.

```bash
# Create namespace, service account, and RBAC
kubectl apply -f tbot-rbac.yaml

# Create tbot configuration
kubectl apply -f tbot-config.yaml

# Deploy tbot DaemonSet
kubectl apply -f tbot-daemonset.yaml
```

**Verify tbot deployment:**

```bash
kubectl get pods -n teleport-system
```

Expected output (one pod per node):
```
NAME         READY   STATUS    RESTARTS   AGE
tbot-xxxxx   1/1     Running   0          30s
tbot-yyyyy   1/1     Running   0          30s
tbot-zzzzz   1/1     Running   0          30s
```

**Check tbot logs:**

```bash
kubectl logs -n teleport-system <tbot-pod-name>
```

Look for successful messages:
```
INFO [TBOT:SVC:] Listener opened for Workload API endpoint addr:/run/spire/sockets/socket
INFO [TBOT:HEAR] Sent heartbeat
```

### Step 8: Deploy Test Application

Deploy a sample application with Istio sidecar injection:

```bash
kubectl apply -f test-app-deployment.yaml
```

**Verify test application:**

```bash
kubectl get pods -n test-app
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
test-app-xxxxxxxxxx-xxxxx   2/2     Running   0          1m
```

Note: `2/2` indicates both the application container and Istio sidecar are running.

### Step 9: Verify SPIFFE Integration

Check that the SPIFFE socket is available in the pod:

```bash
# Get pod name
export POD_NAME=$(kubectl get pod -n test-app -l app=test-app -o jsonpath='{.items[0].metadata.name}')

# Check SPIFFE socket
kubectl exec -n test-app $POD_NAME -c istio-proxy -- ls -la /var/run/secrets/workload-spiffe-uds/
```

Expected output:
```
total 4
drwxr-xr-x 2 root root   60 Dec  5 17:14 .
drwxr-xr-x 8 root root 4096 Dec  5 17:15 ..
srwxrwxrwx 1 root root    0 Dec  5 17:14 socket
```

**Check Istio proxy logs:**

```bash
kubectl logs -n test-app $POD_NAME -c istio-proxy | grep -i "spiffe\|workload"
```

Expected output:
```
Existing workload SDS socket found at var/run/secrets/workload-spiffe-uds/socket
Workload is using file mounted certificates
```

## Support

For issues or questions:
- Teleport documentation: https://goteleport.com/docs/
- Istio documentation: https://istio.io/latest/docs/
- SPIFFE specification: https://github.com/spiffe/spiffe

## Important Notes

1. **Token file security**: The `istio-tbot-token.yaml` file contains sensitive cluster-specific JWKS and is gitignored. NEVER commit this file to version control. Always use the `.template` file for reference.
2. **JWKS is cluster-specific**: Always extract JWKS from your target cluster. Each cluster has unique keys.
3. **Token security**: The join token allows any pod with `teleport-system:tbot` service account to join Teleport. Protect this service account accordingly.
4. **Trust domain**: Must match between Istio and Teleport (use your Teleport cluster domain, e.g., `yourcluster.teleport.sh`)
5. **SPIFFE ID format**: Must include `/sa/` component: `/ns/<namespace>/sa/<service-account>` for Istio compatibility
6. **Path normalization**: Must be `NONE` for SPIFFE compatibility
7. **Socket path**: `/run/spire/sockets/socket` is the standard SPIFFE location
8. **No trailing slashes**: SPIFFE IDs must not have trailing slashes per spec
9. **Restart after changes**: After updating WorkloadIdentity or tbot config, restart tbot pods: `kubectl rollout restart daemonset -n teleport-system tbot`
