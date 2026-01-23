#!/bin/bash
set -e

echo "=== Istio Installation Script ==="
echo ""

# Check if istioctl is available
if ! command -v istioctl &>/dev/null; then
    echo "ERROR: istioctl not found"
    echo "Please install istioctl first"
    exit 1
fi

echo "Using istioctl version: $(istioctl version --remote=false)"
echo ""

# Check if we're connected to a cluster
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Current cluster: $(kubectl config current-context)"
echo ""

# Create istio-system namespace
echo "=== Creating istio-system namespace ==="
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -

# Install Istio with the configuration
echo "=== Installing Istio with SPIFFE integration ==="
istioctl install -f istio-config.yaml -y

# Wait for Istio components to be ready
echo ""
echo "=== Waiting for Istio components to be ready ==="
kubectl wait --for=condition=available --timeout=300s deployment/istiod -n istio-system

echo ""
echo "=== Istio Installation Complete ==="
echo ""
echo "Verifying installation:"
kubectl get pods -n istio-system
echo ""
kubectl get svc -n istio-system
echo ""

echo "✓ Istio installed successfully with SPIFFE integration"
echo ""
echo "Mesh configuration:"
kubectl get configmap istio -n istio-system -o yaml | grep -A 5 "trustDomain\|pathNormalization" || echo "  (configuration will be applied on first pod injection)"
