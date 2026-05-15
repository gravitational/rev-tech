#!/bin/bash
# Cleanup script for the Istio + Teleport Workload Identity demos (Part 1 + Part 2).
# Safe to run multiple times — every deletion is guarded so missing resources are skipped.

# Never abort on error — a cleanup script must always run to completion.
set +e

echo "=== Istio + Teleport Workload Identity Cleanup ==="
echo "This script removes:"
echo "  Part 1: Istio, tbot DaemonSet, Sock Shop, Teleport resources"
echo "  Part 2: demo-vm Docker container, Teleport VM bot/role/identity"
echo ""

# Check cluster connectivity before doing anything
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Current cluster: $(kubectl config current-context)"
if [ -t 0 ]; then
    read -p "Continue with cleanup? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cleanup cancelled"
        exit 0
    fi
else
    echo "Non-interactive mode — proceeding with cleanup."
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 1: Uninstalling Istio ==="
if kubectl get namespace istio-system &>/dev/null; then
    if command -v istioctl &>/dev/null; then
        echo "Using istioctl to uninstall..."
        istioctl uninstall --purge -y 2>/dev/null || echo "  Warning: istioctl uninstall had issues"
    fi

    echo "Deleting istio-system namespace..."
    kubectl delete namespace istio-system --timeout=60s 2>/dev/null || echo "  Warning: namespace deletion timed out"
    kubectl wait --for=delete namespace/istio-system --timeout=120s 2>/dev/null || true
    echo "✓ Istio removed"
else
    echo "  istio-system not found — skipping"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 2: Removing tbot Resources ==="
if kubectl get namespace teleport-system &>/dev/null; then
    kubectl delete daemonsets    -n teleport-system --all --timeout=60s 2>/dev/null || true
    kubectl delete configmaps    -n teleport-system --all --timeout=30s 2>/dev/null || true
    kubectl delete serviceaccounts,roles,rolebindings -n teleport-system --all --timeout=30s 2>/dev/null || true
    kubectl delete clusterrole        tbot --timeout=30s 2>/dev/null || true
    kubectl delete clusterrolebinding tbot --timeout=30s 2>/dev/null || true

    echo "Deleting teleport-system namespace..."
    kubectl delete namespace teleport-system --timeout=60s 2>/dev/null || echo "  Warning: namespace deletion timed out"
    kubectl wait --for=delete namespace/teleport-system --timeout=120s 2>/dev/null || true
    echo "✓ tbot resources removed"
else
    echo "  teleport-system not found — skipping"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 3: Removing Sock Shop ==="
for ns in sock-shop test-app; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo "Deleting $ns namespace..."
        kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || echo "  Warning: $ns namespace deletion timed out"
        kubectl wait --for=delete namespace/"$ns" --timeout=120s 2>/dev/null || true
        echo "✓ $ns removed"
    else
        echo "  $ns not found — skipping"
    fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4: Node Socket Directories ==="
echo "  tbot wrote to /run/spire/sockets on each node."
echo "  Automatic cleanup requires direct node SSH access."
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -E 'worker|node' || true)
if [ -n "$NODES" ]; then
    echo "  To clean up manually, SSH to each node and run:"
    echo "    sudo rm -rf /run/spire/sockets"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 5: Part 2 — VM Container ==="
if command -v docker &>/dev/null && [ -f docker-compose.yml ]; then
    docker compose down 2>/dev/null || true
    echo "✓ demo-vm container stopped and removed"
else
    echo "  docker or docker-compose.yml not found — skipping"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 6: Teleport Server-Side Resources ==="
if ! command -v tctl &>/dev/null; then
    echo "  tctl not found — skipping Teleport resource cleanup"
    echo "  To clean up manually:"
    echo "    tctl rm workload_identity/istio-workloads"
    echo "    tctl rm role/istio-workload-identity-issuer"
    echo "    tctl rm token/istio-tbot-k8s-join"
    echo "    tctl bots rm demo-vm-bot"
    echo "    tctl rm workload_identity/demo-vm-service"
    echo "    tctl rm role/demo-vm-workload-identity"
elif ! tctl status &>/dev/null; then
    echo "  Not logged in to Teleport (run: tsh login) — skipping Teleport resource cleanup"
    echo "  To clean up manually:"
    echo "    tctl rm workload_identity/istio-workloads"
    echo "    tctl rm role/istio-workload-identity-issuer"
    echo "    tctl rm token/istio-tbot-k8s-join"
    echo "    tctl bots rm demo-vm-bot"
    echo "    tctl rm workload_identity/demo-vm-service"
    echo "    tctl rm role/demo-vm-workload-identity"
else
    echo "--- Part 1 ---"
    tctl rm workload_identity/istio-workloads        2>/dev/null && echo "✓ workload_identity/istio-workloads" || echo "  workload_identity/istio-workloads not found"
    tctl rm role/istio-workload-identity-issuer      2>/dev/null && echo "✓ role/istio-workload-identity-issuer" || echo "  role/istio-workload-identity-issuer not found"
    tctl rm token/istio-tbot-k8s-join               2>/dev/null && echo "✓ token/istio-tbot-k8s-join" || echo "  token/istio-tbot-k8s-join not found"

    echo "--- Part 2 ---"
    tctl bots rm demo-vm-bot                         2>/dev/null && echo "✓ bot/demo-vm-bot" || echo "  bot/demo-vm-bot not found"
    tctl rm workload_identity/demo-vm-service        2>/dev/null && echo "✓ workload_identity/demo-vm-service" || echo "  workload_identity/demo-vm-service not found"
    tctl rm role/demo-vm-workload-identity           2>/dev/null && echo "✓ role/demo-vm-workload-identity" || echo "  role/demo-vm-workload-identity not found"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 7: Local Generated Files ==="
for f in istio/istio-tbot-token.yaml .env.vm; do
    if [ -f "$f" ]; then
        rm -f "$f" && echo "✓ Deleted $f" || echo "  Warning: could not delete $f"
    else
        echo "  $f not found — skipping"
    fi
done

# Check for any stray token files
TOKEN_FILES=$(ls *-token*.yaml 2>/dev/null | grep -v ".template" || true)
if [ -n "$TOKEN_FILES" ]; then
    echo ""
    echo "  Found other token files (gitignored, safe to delete if not needed):"
    echo "$TOKEN_FILES" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Cleanup Complete ==="
LEFTOVER=$(kubectl get namespaces 2>/dev/null | grep -E 'istio-system|teleport-system|sock-shop|test-app' || true)
if [ -n "$LEFTOVER" ]; then
    echo "WARNING: some namespaces still present:"
    echo "$LEFTOVER"
else
    echo "✓ No demo namespaces remaining"
fi
echo ""
echo "NOTE: /run/spire/sockets on worker nodes may need manual cleanup (see Phase 4 above)."
