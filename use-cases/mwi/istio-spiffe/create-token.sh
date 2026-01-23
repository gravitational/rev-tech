#!/bin/bash
# Helper script to create cluster-specific Teleport join token
# This script extracts the cluster's JWKS and creates istio-tbot-token.yaml
#
# The generated istio-tbot-token.yaml file is gitignored and should NOT be committed

set -e

echo "=== Teleport Join Token Creation Script ==="
echo ""

# Check if template exists
if [ ! -f "istio-tbot-token.yaml.template" ]; then
    echo "ERROR: istio-tbot-token.yaml.template not found"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Check kubectl connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "Please ensure kubectl is configured and you have cluster access"
    exit 1
fi

echo "Current cluster: $(kubectl config current-context)"
echo ""

# Warn if token file already exists
if [ -f "istio-tbot-token.yaml" ]; then
    echo "WARNING: istio-tbot-token.yaml already exists"
    read -p "Do you want to overwrite it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "=== Extracting cluster JWKS ==="
JWKS=$(kubectl get --raw /openid/v1/jwks)

if [ -z "$JWKS" ]; then
    echo "ERROR: Failed to extract JWKS from cluster"
    exit 1
fi

echo "Successfully extracted JWKS"
echo ""

echo "=== Creating istio-tbot-token.yaml ==="
# Copy template
cp istio-tbot-token.yaml.template istio-tbot-token.yaml

# Escape quotes in JWKS for sed
ESCAPED_JWKS=$(echo "$JWKS" | sed 's/"/\\"/g')

# Replace placeholder with actual JWKS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|'PASTE_JWKS_HERE'|'$ESCAPED_JWKS'|" istio-tbot-token.yaml
else
    # Linux
    sed -i "s|'PASTE_JWKS_HERE'|'$ESCAPED_JWKS'|" istio-tbot-token.yaml
fi

echo "Successfully created istio-tbot-token.yaml"
echo ""

echo "=== Next Steps ==="
echo "1. Review the generated file: cat istio-tbot-token.yaml"
echo "2. Create the token in Teleport: tctl create -f istio-tbot-token.yaml"
echo "3. Verify token creation: tctl get token/istio-tbot-k8s-join"
echo ""
echo "IMPORTANT: istio-tbot-token.yaml is gitignored and should NOT be committed"
echo "           This file contains cluster-specific secrets"
