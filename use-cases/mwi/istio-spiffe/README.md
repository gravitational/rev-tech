# Istio + Teleport Workload Identity Integration

This project demonstrates the integration of Teleport's Workload Identity service with Istio service mesh, enabling SPIFFE-compliant workload identities for Kubernetes applications.

## Overview

This integration provides:

- **Teleport-issued SPIFFE identities**: Workloads receive cryptographic identities from Teleport instead of Istio's built-in CA
- **Centralized identity management**: Manage workload identities across multiple clusters from a single Teleport instance
- **SPIFFE Workload API compliance**: Standard SPIFFE implementation via Unix domain socket
- **Istio mesh integration**: Seamless integration with Istio's service mesh capabilities

## Architecture

![](images/tbot-istio.png)

## Components

### Istio Configuration
- **Trust Domain**: `cluster.local`
- **Path Normalization**: Disabled (NONE) for SPIFFE compatibility
- **Certificate Provider**: External (Teleport via SPIFFE Workload API)

### Teleport Components
- **Bot Role**: `istio-workload-identity-issuer` - Allows issuing workload identities with `env:dev` label
- **Workload Identity**: `istio-workloads` - Defines SPIFFE ID template for Kubernetes workloads
- **Join Method**: Kubernetes with static JWKS validation

### Kubernetes Resources
- **Namespace**: `teleport-system` - Contains tbot DaemonSet
- **tbot DaemonSet**: Runs on each node, provides Workload Identity API via Unix socket
- **SPIFFE Socket**: `/run/spire/sockets/socket` - Standard SPIFFE Workload API endpoint

## SPIFFE ID Format

Workloads receive SPIFFE IDs following the Istio-compatible pattern:

```
spiffe://<teleport-domain>/ns/<namespace>/sa/<service-account>
```

Example:
```
spiffe://<teleport-domain>/ns/test-app/sa/test-app
```

## Prerequisites

- Kubernetes cluster (1.27+)
- `kubectl` configured with cluster access
- `istioctl` (1.28+)
- Active Teleport cluster with admin access
- `tctl` and `tsh` configured

## Istio Install

See [INSTALLATION.md](INSTALLATION.md) for detailed installation instructions of Istio and Tbot


## Sock Shop Demo Application

**What Works**:
- ✅ Teleport issues SPIFFE certificates correctly
- ✅ Pods receive certificates with proper SPIFFE IDs
- ✅ Trust domain configuration matches
- ✅ External access to services works
- ✅ Service-to-service mTLS validation succeeds with Teleport-issued certificates

For a comprehensive demonstration attempt See [SOCK-SHOP-DEMO.md](SOCK-SHOP-DEMO.md) for detailed installation instructions of Istio and Tbot

```bash
# Deploy the Sock Shop demo
kubectl apply -f sock-shop-demo.yaml

# Wait for all pods to be ready
kubectl get pods -n sock-shop -w

# Test baseline functionality
FRONTEND_IP=$(kubectl get svc -n sock-shop front-end -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$FRONTEND_IP/  # External access works
curl http://$FRONTEND_IP/catalogue  # Backend service fails with cert error
```

See [SOCK-SHOP-DEMO.md](SOCK-SHOP-DEMO.md) for detailed setup steps and investigation notes embedded there.

## Files

### Configuration Files (Safe to Commit)
- `istio-install.sh` - Automated Istio installation script
- `istio-config.yaml` - Istio configuration with SPIFFE integration
- `create-token.sh` - Helper script to create cluster-specific join token
- `cleanup.sh` - Comprehensive cleanup script for all resources
- `teleport-bot-role.yaml` - Teleport role for workload identity issuer
- `teleport-workload-identity.yaml` - Workload identity definition
- `istio-tbot-token.yaml.template` - Template for Kubernetes join token (copy and customize)
- `tbot-rbac.yaml` - Kubernetes RBAC for tbot
- `tbot-config.yaml` - tbot configuration
- `tbot-daemonset.yaml` - tbot DaemonSet deployment
- `test-app-deployment.yaml` - Sample application with Istio injection
- `sock-shop-demo.yaml` - Sock Shop microservices demo application
- `sock-shop-deny-all.yaml` - Default deny-all policy for zero-trust demonstration
- `sock-shop-policies.yaml` - Complete Istio authorization policies using SPIFFE IDs

### Generated Files (Gitignored - DO NOT COMMIT)
- `istio-tbot-token.yaml` - Cluster-specific join token with JWKS (generated from template)

**Security Note**: The `istio-tbot-token.yaml` file contains sensitive cluster-specific JWKS and should never be committed to version control. It is automatically excluded via `.gitignore`.

## Key Configuration Notes

### SPIFFE Socket Path
The configuration uses `/run/spire/sockets/socket` as the socket path, which matches the standard SPIFFE Workload API location. This eliminates the need for symlinks or custom path configurations.

### Trust Domain
Must match between Istio (`ellinj.teleport.sh`) and the workload's SPIFFE ID prefix.

### Path Normalization
Set to `NONE` in Istio configuration to maintain SPIFFE ID compatibility.

### No Trailing Slash
SPIFFE IDs must NOT have trailing slashes per the SPIFFE specification.

### Istio injection template (`spire`)
The custom `spire` template in `istio-config.yaml` adds the SPIFFE Workload API socket mount and sets `CA_ADDR`/`PILOT_CERT_PROVIDER` so the Envoy sidecar uses Teleport-issued identities. Enable it alongside the default sidecar template with the annotation `inject.istio.io/templates: "sidecar,spire"`:

```yaml
# Per-namespace
apiVersion: v1
kind: Namespace
metadata:
  name: test-app
  labels:
    istio-injection: enabled
  annotations:
    inject.istio.io/templates: "sidecar,spire"
```

```yaml
# Per-workload (Deployment pod template)
metadata:
  annotations:
    inject.istio.io/templates: "sidecar,spire"
```

Setting it at the namespace level applies to every injected Pod in the namespace; setting it on a workload overrides or augments whatever is defined on the namespace.

## Cleanup

To completely remove all installed components:

```bash
./cleanup.sh
```

The cleanup script removes:
- Istio components (istio-system namespace)
- tbot DaemonSet and resources (teleport-system namespace)
- Test application (test-app namespace)
- Teleport server-side resources (role, workload identity, token via tctl)
- Local generated token files (optional, with confirmation)

The cleanup script is self-contained; see its inline help for options.

## Resources

- [Teleport Workload Identity Documentation](https://goteleport.com/docs/machine-id/workload-identity/)
- [Istio Certificate Management](https://istio.io/latest/docs/tasks/security/cert-management/)
- [SPIFFE Specification](https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE.md)

