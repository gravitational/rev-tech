#!/bin/bash
set -e

echo "=== Istio + tbot Cleanup Script ==="
echo "This script will remove:"
echo "  - Istio components (istio-system namespace)"
echo "  - tbot DaemonSet and resources (teleport-system namespace)"
echo "  - Test application (test-app namespace)"
echo "  - Sock Shop demo (sock-shop namespace)"
echo "  - Teleport server-side resources (role, workload identity, token)"
echo "  - Local generated token files (optional)"
echo ""

# Check if we're connected to a cluster
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Current cluster: $(kubectl config current-context)"
read -p "Continue with cleanup? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "=== Phase 1: Uninstalling Istio ==="
if kubectl get namespace istio-system &>/dev/null; then
    echo "Found istio-system namespace, attempting to uninstall Istio..."

    # Try using istioctl if available
    if command -v istioctl &>/dev/null; then
        echo "Using istioctl to uninstall..."
        istioctl uninstall --purge -y || echo "Warning: istioctl uninstall had issues"
    fi

    # Delete the namespace
    echo "Deleting istio-system namespace..."
    kubectl delete namespace istio-system --timeout=60s || echo "Warning: istio-system namespace deletion timed out"

    echo "Waiting for istio-system namespace to be fully deleted..."
    kubectl wait --for=delete namespace/istio-system --timeout=120s || echo "Warning: namespace still exists"
else
    echo "No istio-system namespace found, skipping Istio uninstall"
fi

echo ""
echo "=== Phase 2: Removing tbot Resources ==="
if kubectl get namespace teleport-system &>/dev/null; then
    echo "Found teleport-system namespace..."

    # Delete DaemonSets first
    echo "Deleting tbot DaemonSets..."
    kubectl delete daemonsets -n teleport-system --all --timeout=60s || echo "Warning: DaemonSet deletion had issues"

    # Delete ConfigMaps
    echo "Deleting ConfigMaps..."
    kubectl delete configmaps -n teleport-system --all --timeout=30s || echo "Warning: ConfigMap deletion had issues"

    # Delete RBAC resources
    echo "Deleting ServiceAccounts, Roles, and RoleBindings..."
    kubectl delete serviceaccounts,roles,rolebindings -n teleport-system --all --timeout=30s || echo "Warning: RBAC deletion had issues"

    # Delete ClusterRoles and ClusterRoleBindings (if any with tbot prefix)
    echo "Deleting ClusterRole and ClusterRoleBinding resources..."
    kubectl delete clusterrole tbot --timeout=30s 2>/dev/null || echo "No tbot ClusterRole found"
    kubectl delete clusterrolebinding tbot --timeout=30s 2>/dev/null || echo "No tbot ClusterRoleBinding found"

    # Delete the namespace
    echo "Deleting teleport-system namespace..."
    kubectl delete namespace teleport-system --timeout=60s || echo "Warning: teleport-system namespace deletion timed out"

    echo "Waiting for teleport-system namespace to be fully deleted..."
    kubectl wait --for=delete namespace/teleport-system --timeout=120s || echo "Warning: namespace still exists"
else
    echo "No teleport-system namespace found, skipping tbot cleanup"
fi

echo ""
echo "=== Phase 3: Cleaning Up Node Resources ==="
echo "Checking for symlinks and socket directories on nodes..."

# Get list of worker nodes
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E 'worker|node' || echo "")

if [ -z "$NODES" ]; then
    echo "No worker nodes found or unable to determine node names"
    echo "You may need to manually clean up /run/spire/sockets on each node if they exist"
else
    for NODE in $NODES; do
        echo "Node: $NODE"
        echo "  To clean up manually, SSH to the node and run:"
        echo "    sudo rm -rf /run/spire/sockets"
        echo ""
    done

    echo "NOTE: Automatic cleanup of node resources requires direct SSH access."
    echo "If you have SSH access to the nodes, you can run:"
    echo "  for node in $NODES; do"
    echo "    ssh \$node 'sudo rm -rf /run/spire/sockets'"
    echo "  done"
fi

echo ""
echo "=== Phase 4: Cleaning Up Test Workloads ==="
# Look for test applications in common namespaces
for ns in default test-app; do
    if kubectl get namespace $ns &>/dev/null; then
        echo "Checking namespace $ns for test workloads..."
        kubectl delete deployments,services,serviceaccounts -n $ns -l app=test-app --timeout=30s 2>/dev/null || echo "No test workloads found in $ns"
    fi
done

# Delete test-app namespace if it exists
if kubectl get namespace test-app &>/dev/null; then
    echo "Deleting test-app namespace..."
    kubectl delete namespace test-app --timeout=60s || echo "Warning: test-app namespace deletion timed out"
    kubectl wait --for=delete namespace/test-app --timeout=120s || echo "Warning: test-app namespace still exists"
else
    echo "No test-app namespace found"
fi

# Delete sock-shop namespace if it exists
if kubectl get namespace sock-shop &>/dev/null; then
    echo "Deleting sock-shop demo namespace..."
    kubectl delete namespace sock-shop --timeout=60s || echo "Warning: sock-shop namespace deletion timed out"
    kubectl wait --for=delete namespace/sock-shop --timeout=120s || echo "Warning: sock-shop namespace still exists"
else
    echo "No sock-shop namespace found"
fi

echo ""
echo "=== Phase 5: Teleport Server-Side Resources ==="
echo "Checking for Teleport resources (requires tctl and active tsh session)..."
echo ""

# Check if tctl is available
if command -v tctl &>/dev/null; then
    if tctl status &>/dev/null; then
        echo "Deleting Teleport workload identity..."
        tctl rm workload_identity/istio-workloads 2>/dev/null || echo "  Workload identity not found or already deleted"

        echo "Deleting Teleport bot role..."
        tctl rm role/istio-workload-identity-issuer 2>/dev/null || echo "  Role not found or already deleted"

        echo "Deleting Teleport join token..."
        tctl rm token/istio-tbot-k8s-join 2>/dev/null || echo "  Token not found or already deleted"

        echo "✓ Teleport resources cleaned up"
    else
        echo "WARNING: Not logged in to Teleport (tsh login required)"
        echo "To manually clean up Teleport resources, run:"
        echo "  tctl rm workload_identity/istio-workloads"
        echo "  tctl rm role/istio-workload-identity-issuer"
        echo "  tctl rm token/istio-tbot-k8s-join"
    fi
else
    echo "WARNING: tctl not found"
    echo "To manually clean up Teleport resources, run:"
    echo "  tctl rm workload_identity/istio-workloads"
    echo "  tctl rm role/istio-workload-identity-issuer"
    echo "  tctl rm token/istio-tbot-k8s-join"
fi

echo ""
echo "=== Phase 6: Local Generated Files ==="
echo "Checking for locally generated token files..."
if [ -f "istio-tbot-token.yaml" ]; then
    echo "Found istio-tbot-token.yaml (cluster-specific, safe to delete)"
    read -p "Delete istio-tbot-token.yaml? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f istio-tbot-token.yaml
        echo "✓ Deleted istio-tbot-token.yaml"
    else
        echo "  Skipped deletion (file contains cluster-specific JWKS)"
    fi
else
    echo "No istio-tbot-token.yaml found"
fi

# Check for any other token files
TOKEN_FILES=$(ls *-token*.yaml 2>/dev/null | grep -v ".template" || true)
if [ -n "$TOKEN_FILES" ]; then
    echo ""
    echo "Found other token files:"
    echo "$TOKEN_FILES"
    echo "These files are gitignored and can be safely deleted if no longer needed."
fi

echo ""
echo "=== Cleanup Summary ==="
echo "✓ Istio components removed"
echo "✓ tbot resources removed"
echo "✓ Namespaces cleaned up"
echo "✓ Teleport server resources cleaned up (if tctl available)"
echo ""
echo "NOTE: You may need to manually remove /run/spire/sockets on worker nodes"
echo ""
echo "Remaining namespaces:"
kubectl get namespaces | grep -E 'istio|teleport|test-app|sock-shop' || echo "  No Istio, Teleport, test-app, or sock-shop namespaces found ✓"
echo ""
echo "Cleanup complete! Ready for fresh installation."
