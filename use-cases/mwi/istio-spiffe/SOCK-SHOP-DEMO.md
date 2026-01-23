# Sock Shop Demo: Verifying Teleport Workload Identity with Istio

This guide demonstrates how to verify that Teleport Workload Identity is wired into Istio using the Sock Shop microservices application, including end-to-end mTLS.

## Overview

The Sock Shop application is a microservices demo that consists of multiple services communicating with each other. This makes it ideal for demonstrating:

1. **SPIFFE ID issuance** - Each service gets a unique identity
2. **mTLS between services** - All communication is encrypted and authenticated
3. **Identity-based authorization** - Services can only call authorized endpoints
4. **Workload attestation** - Teleport verifies pod identity via Kubernetes

## Architecture


![Sock Shop](images/sock-shop.png)

Each service has:
- Unique ServiceAccount
- Istio sidecar proxy
- SPIFFE ID from Teleport
- mTLS certificates
```

## Prerequisites

Complete the main installation:
- Istio installed with SPIFFE integration
- tbot DaemonSet running on all nodes
- Teleport workload identity configured

## Quick Reference: Verification Commands

Here are the key commands for verifying the integration (use after deployment).

```bash
# Set pod name variable
export POD_NAME=$(kubectl get pod -n sock-shop -l app=catalogue -o jsonpath='{.items[0].metadata.name}')

# 1. Verify SPIFFE socket exists
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- ls -la /var/run/secrets/workload-spiffe-uds/

# 2. Check Istio proxy detected SPIFFE socket
kubectl logs -n sock-shop $POD_NAME -c istio-proxy | grep -i "spiffe\|workload"

# 3. Verify mTLS is active (check for connection_security_policy.mutual_tls)
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- \
  curl -s localhost:15000/stats | grep "connection_security_policy.mutual_tls" | head -1

# 4. View SPIFFE IDs in use
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- \
  curl -s localhost:15000/stats | grep -o "spiffe://[^.]*\.[^.]*\.[^.]*\.[^.]*\.[^.]*\.[^.]*" | sort -u

# 5. View certificate details
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- \
  curl -s localhost:15000/certs
```

## Step 1: Deploy Sock Shop Application

Deploy the application with Istio sidecar injection enabled:

```bash
kubectl apply -f sock-shop-demo.yaml
```

**Wait for all pods to be ready:**

```bash
kubectl get pods -n sock-shop -w
```

Expected output (after 1-2 minutes):
```
NAME                            READY   STATUS    RESTARTS   AGE
carts-xxxxxxxxxx-xxxxx          2/2     Running   0          1m
catalogue-xxxxxxxxxx-xxxxx      2/2     Running   0          1m
catalogue-db-xxxxxxxxxx-xxxxx   2/2     Running   0          1m
front-end-xxxxxxxxxx-xxxxx      2/2     Running   0          1m
orders-xxxxxxxxxx-xxxxx         2/2     Running   0          1m
```

Note: Each pod should show `2/2` (application + Istio sidecar).

## Step 2: Verify SPIFFE Socket in Pods

Check that each pod has access to the SPIFFE Workload API socket:

```bash
# Pick any pod
POD_NAME=$(kubectl get pod -n sock-shop -l app=catalogue -o jsonpath='{.items[0].metadata.name}')

# Verify socket exists
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- ls -la /var/run/secrets/workload-spiffe-uds/
```

Expected output:
```
total 4
drwxr-xr-x 2 root root   60 Dec  5 17:14 .
drwxr-xr-x 8 root root 4096 Dec  5 17:15 ..
srwxrwxrwx 1 root root    0 Dec  5 17:14 socket
```

## Step 3: Verify Istio Proxy Detects SPIFFE Identities

Check Istio proxy logs to confirm it's using the Teleport SPIFFE socket:

```bash
kubectl logs -n sock-shop $POD_NAME -c istio-proxy | grep -i "spiffe\|workload"
```

Expected output:
```
Existing workload SDS socket found at var/run/secrets/workload-spiffe-uds/socket
Workload is using file mounted certificates
```

## Step 4: Verify SPIFFE IDs Are Issued

Check what SPIFFE ID each service has:

```bash
# Use the validation script
./validate-spiffe-ids.sh
```

Expected output:
```
=== Service: front-end ===
Pod: front-end-xxxxxxxxx-xxxxx
ServiceAccount: front-end
Expected SPIFFE ID: spiffe://ellinj.teleport.sh/ns/sock-shop/sa/front-end
Actual SPIFFE ID:   spiffe://ellinj.teleport.sh/ns/sock-shop/sa/front-end
✅ SPIFFE ID matches!

=== Service: catalogue ===
Pod: catalogue-xxxxxxxxx-xxxxx
ServiceAccount: catalogue
Expected SPIFFE ID: spiffe://ellinj.teleport.sh/ns/sock-shop/sa/catalogue
Actual SPIFFE ID:   spiffe://ellinj.teleport.sh/ns/sock-shop/sa/catalogue
✅ SPIFFE ID matches!

=== Service: carts ===
Pod: carts-xxxxxxxxx-xxxxx
ServiceAccount: carts
Expected SPIFFE ID: spiffe://ellinj.teleport.sh/ns/sock-shop/sa/carts
Actual SPIFFE ID:   spiffe://ellinj.teleport.sh/ns/sock-shop/sa/carts
✅ SPIFFE ID matches!

=== Service: orders ===
Pod: orders-xxxxxxxxx-xxxxx
ServiceAccount: orders
Expected SPIFFE ID: spiffe://ellinj.teleport.sh/ns/sock-shop/sa/orders
Actual SPIFFE ID:   spiffe://ellinj.teleport.sh/ns/sock-shop/sa/orders
✅ SPIFFE ID matches!
```

Note: Replace `ellinj.teleport.sh` with your actual Teleport cluster domain.

## Step 5: Test Service Communication (Without Policies)

Access the front-end service and verify it can communicate with backend services:

```bash
# Get front-end service endpoint
FRONTEND_IP=$(kubectl get svc -n sock-shop front-end -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test catalogue endpoint
curl http://$FRONTEND_IP/catalogue

# Should return JSON with sock products
```

Check that services are communicating with mTLS:

```bash
# View Istio proxy stats for mTLS connections
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- \
  curl -s localhost:15000/stats | grep "connection_security_policy.mutual_tls"

# Or get just the request count
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- \
  curl -s localhost:15000/stats | grep "istio_requests_total.*mutual_tls:" | head -1
```

You should see metrics with `connection_security_policy.mutual_tls`, indicating mTLS is working.

The metrics will also show SPIFFE IDs:
- `source_principal.spiffe://ellinj.teleport.sh/ns/sock-shop/sa/front-end`
- `destination_principal.spiffe://ellinj.teleport.sh/ns/sock-shop/sa/catalogue`

## Step 6: Apply Deny-All Policy (Break the Application)

Now let's apply a **default deny-all policy** to demonstrate zero-trust security. This will block all traffic and break the application:

```bash
kubectl apply -f sock-shop-deny-all.yaml
```

This applies a single policy that denies all traffic in the sock-shop namespace.

**Test that the application is now broken:**

```bash
# Try to access catalogue - this should FAIL
curl http://$FRONTEND_IP/catalogue

# You should see connection errors or timeouts
```

**Check the Istio proxy logs to see denials:**

```bash
kubectl logs -n sock-shop $POD_NAME -c istio-proxy --tail=20
```

You should see messages about RBAC denials.

**Try accessing from front-end directly:**

```bash
FRONTEND_POD=$(kubectl get pod -n sock-shop -l app=front-end -o jsonpath='{.items[0].metadata.name}')

# This should fail with RBAC: access denied
kubectl exec -n sock-shop $FRONTEND_POD -c front-end -- \
  curl -v http://catalogue/catalogue
```

Expected output:
```
RBAC: access denied
```

**What this demonstrates:**
- ✅ Default deny-all policy blocks everything
- ✅ Zero-trust model requires explicit allows
- ✅ SPIFFE-based authorization is enforced
- ✅ Even services with valid identities are blocked without allow rules

## Step 7: Apply Allow Policies (Fix the Application)

Now let's apply the complete policy set with explicit allow rules based on SPIFFE IDs:

```bash
kubectl apply -f sock-shop-policies.yaml
```

This applies:
- **Default deny-all** policy (same as before)
- **Allow policies** based on SPIFFE IDs (NEW)
- **Strict mTLS** enforcement

## Step 8: Verify Authorization Policies Work

Test that the application still works with policies:

```bash
# Should work - front-end can call catalogue
curl http://$FRONTEND_IP/catalogue

# Should work - front-end UI loads
curl http://$FRONTEND_IP/
```

**Test unauthorized access:**

Try to access catalogue directly from a different pod that shouldn't have access:

```bash
# Create a test pod without proper identity
kubectl run test-curl -n sock-shop --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl http://catalogue/catalogue

# This should be DENIED with "RBAC: access denied"
```

Expected output:
```
RBAC: access denied
```

This proves that:
1. Only services with proper SPIFFE IDs can communicate
2. Authorization is enforced based on workload identity
3. Teleport-issued identities are being validated by Istio
4. The application works again after applying allow policies

## Step 9: Verify Certificate Chain

Check that certificates are issued by Teleport (not Istio's CA):

```bash
# Get certificate info from Envoy
kubectl exec -n sock-shop $POD_NAME -c istio-proxy -- \
  curl -s localhost:15000/certs | grep -A 10 "Certificate Chain"
```

Look for certificate details. The certificate should have:
- Subject Alternative Name (SAN) with SPIFFE ID: `spiffe://ellinj.teleport.sh/ns/sock-shop/sa/<service-account>`
- Issued by Teleport's workload identity CA

## Step 10: Monitor Workload Identity Usage in Teleport

Check Teleport audit logs to see workload identity issuance events:

```bash
# View recent workload identity events
tctl events list --type=workload_identity.issue --count=20
```

You should see events showing SPIFFE SVIDs being issued to the sock-shop services.

## Step 11: Test Policy Violations

Create a test scenario where a service tries to access an unauthorized endpoint:

```bash
# Try to have front-end access catalogue-db directly (should fail)
FRONTEND_POD=$(kubectl get pod -n sock-shop -l app=front-end -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n sock-shop $FRONTEND_POD -c front-end -- \
  curl -v http://catalogue-db:3306

# Should be blocked by AuthorizationPolicy
```

Expected: Connection refused or RBAC denial, proving that front-end cannot bypass catalogue to access the database.

## Verification Checklist

After completing all steps, verify:

- [ ] All sock-shop pods running with 2/2 containers (app + sidecar)
- [ ] SPIFFE socket present in all pods
- [ ] Istio proxy logs show workload socket detection
- [ ] Each service has unique SPIFFE ID
- [ ] Front-end can access backend services (before policies)
- [ ] mTLS connections shown in Envoy stats
- [ ] Application breaks with deny-all policy (Step 6)
- [ ] Application recovers with allow policies (Step 7)
- [ ] Authorized access works (front-end → catalogue)
- [ ] Unauthorized access is denied (test pod → catalogue)
- [ ] Certificates issued by Teleport (not Istio CA)
- [ ] Workload identity events visible in Teleport audit logs

## Understanding the SPIFFE IDs

Each service receives a SPIFFE ID in this format:

```
spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>
```

Examples (using `ellinj.teleport.sh` as the trust domain):
- Front-end: `spiffe://ellinj.teleport.sh/ns/sock-shop/sa/front-end`
- Catalogue: `spiffe://ellinj.teleport.sh/ns/sock-shop/sa/catalogue`
- Carts: `spiffe://ellinj.teleport.sh/ns/sock-shop/sa/carts`

Note: The trust domain should match your Teleport cluster domain (without port number).

These IDs are:
1. **Unique per service** - Based on Kubernetes ServiceAccount
2. **Cryptographically verified** - Signed by Teleport's CA
3. **Short-lived** - Rotated automatically by tbot
4. **Attestable** - Verified against Kubernetes API

## Authorization Policy Examples

The policies demonstrate several patterns:

### 1. Default Deny
```yaml
spec: {}  # Empty spec denies all traffic
```

### 2. Allow Based on SPIFFE ID
```yaml
- from:
  - source:
      principals:
      - "cluster.local/ns/sock-shop/sa/front-end"
```

Note: Istio strips the `spiffe://` prefix in authorization policies.

### 3. Restrict Methods and Paths
```yaml
- to:
  - operation:
      methods: ["GET"]
      paths: ["/catalogue*", "/health"]
```

### 4. Database Access Control
```yaml
# Only catalogue service can access catalogue-db on port 3306
- from:
  - source:
      principals:
      - "cluster.local/ns/sock-shop/sa/catalogue"
  to:
  - operation:
      ports: ["3306"]
```

## Troubleshooting

### Issue: Pods stuck in Init state

```bash
kubectl describe pod -n sock-shop <pod-name>
```

Check for:
- Istio injection enabled on namespace
- tbot running on the same node

### Issue: Services can't communicate with databases (MongoDB/MySQL)

**Symptom:** Application services show connection errors when trying to reach database pods:
- `MongoSocketReadException: Prematurely reached end of stream`
- `Connection refused` or `Connection reset`

**Root Cause:** Database services (carts-db, catalogue-db) require explicit `DestinationRule` configuration because:
1. They use raw TCP protocols (not HTTP)
2. Istio cannot auto-detect mTLS for non-HTTP traffic
3. The client needs explicit instruction to wrap TCP in mTLS

**Solution:** Create a `DestinationRule` AND `PeerAuthentication` for each database service:

```yaml
# Client-side: tells carts to use mTLS when connecting to carts-db
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: carts-db
  namespace: sock-shop
spec:
  host: carts-db.sock-shop.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
# Server-side: enables proper mTLS negotiation for MongoDB
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: carts-db-mtls
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      app: carts-db
  mtls:
    mode: STRICT
```

**Why both are needed:**
- `DestinationRule`: Tells the **client** (carts) to use mTLS for the TCP connection
- `PeerAuthentication`: Ensures the **server** (carts-db) properly negotiates mTLS for non-HTTP protocols
- Even though namespace-level STRICT mTLS is set, workload-specific policies trigger additional Envoy configuration needed for database protocols

**Why HTTP services don't need this:** Istio's Envoy proxy can auto-detect and auto-negotiate mTLS for HTTP traffic based on `PeerAuthentication` policies. For databases, both explicit policies are required.

**Service Port Naming:** Also ensure database service ports are properly named (e.g., `name: mongo`, `name: mysql`) to help Istio recognize the protocol:

```yaml
spec:
  ports:
  - name: mongo  # Named port helps Istio
    port: 27017
    targetPort: 27017
```

### Issue: Services can't communicate

```bash
# Check Envoy access logs
kubectl logs -n sock-shop <pod-name> -c istio-proxy --tail=50

# Look for HTTP 403 (RBAC denials) or connection errors
```

### Issue: RBAC access denied

This is expected behavior when:
- Authorization policies are applied
- Service doesn't have the right SPIFFE ID
- Calling an unauthorized endpoint

Check the policy allows the specific service and path.

### Issue: No SPIFFE socket

```bash
# Check tbot is running on the node
NODE=$(kubectl get pod -n sock-shop <pod-name> -o jsonpath='{.spec.nodeName}')
kubectl get pods -n teleport-system -o wide | grep $NODE

# If no tbot pod, check DaemonSet
kubectl get daemonset -n teleport-system
```

### Issue: Kiali shows "Service Account not found for this principal" warning

**Symptom:** Kiali displays validation warnings on AuthorizationPolicy resources showing principals are invalid.

**Root Cause:** Kiali doesn't recognize custom trust domains (like `ellinj.teleport.sh`) by default. It expects either:
- Standard Kubernetes trust domain: `cluster.local`
- Full SPIFFE URI format: `spiffe://ellinj.teleport.sh/...`

**Why your policies still work:** Istio automatically prepends `spiffe://` to principals at runtime. The format `ellinj.teleport.sh/ns/sock-shop/sa/carts` is correct for Istio, even though Kiali doesn't validate it properly.

**Solution:** Configure Kiali to recognize your custom trust domain:

```bash
# Edit Kiali ConfigMap
kubectl edit configmap kiali -n istio-system

# Add under external_services.istio:
external_services:
  istio:
    root_namespace: istio-system
    istio_identity_domain: ellinj.teleport.sh  # Add this line

# Restart Kiali
kubectl rollout restart deployment/kiali -n istio-system
```

**Principal Format Rules:**
- **Do NOT** include `spiffe://` prefix in AuthorizationPolicy principals
- Istio auto-prepends it during runtime conversion to Envoy config
- Including it yourself results in `spiffe://spiffe://...` which breaks matching
- Correct format: `"ellinj.teleport.sh/ns/sock-shop/sa/carts"`
- Incorrect format: `"spiffe://ellinj.teleport.sh/ns/sock-shop/sa/carts"`

Verify the fix:
```bash
# Check actual SPIFFE ID in certificate
kubectl exec -n sock-shop deploy/carts -c istio-proxy -- \
  curl -s localhost:15000/config_dump | \
  jq -r '.configs[] | select(."@type" == "type.googleapis.com/envoy.admin.v3.SecretsConfigDump") | .dynamic_active_secrets[0].secret.tls_certificate.certificate_chain.inline_bytes' | \
  base64 -d | openssl x509 -text -noout 2>/dev/null | grep -A2 "Subject Alternative Name"

# Expected: URI:spiffe://ellinj.teleport.sh/ns/sock-shop/sa/carts
```

## Cleanup

Remove the sock shop deployment:

```bash
kubectl delete namespace sock-shop
```

Or use the main cleanup script to remove everything:

```bash
./cleanup.sh
```

## Next Steps

1. **Add more services** - Expand the mesh with additional microservices
2. **Implement observability** - Use Istio telemetry to track identity-based metrics
3. **Test failure scenarios** - Simulate compromised workloads and policy violations
4. **Integrate with Teleport RBAC** - Use Teleport roles to control which workloads can get identities
5. **Audit and compliance** - Review Teleport audit logs for identity usage

## Key Takeaways

This demo proves that:

✅ **Teleport issues SPIFFE identities** to all services in the mesh
✅ **Istio uses Teleport certificates** instead of its own CA
✅ **mTLS works correctly** with Teleport-issued certificates
✅ **Service-to-service communication** works with proper SPIFFE ID format
✅ **Authorization policies** can use SPIFFE IDs for access control
✅ **Zero-trust networking** is achieved through workload identity verification
✅ **Audit trail** exists in Teleport for all identity operations
✅ **MySQL and other TCP services** work correctly through Istio's mTLS proxy

**Key Success Factor**: The SPIFFE ID template must include the `/sa/` component (`/ns/{namespace}/sa/{service-account}`) to match Istio's expectations. This was the critical fix that enabled full mTLS functionality.

This provides a strong foundation for secure, identity-based microservices communication.
