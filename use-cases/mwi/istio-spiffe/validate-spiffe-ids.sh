#!/bin/bash

# Validate SPIFFE IDs for sock-shop services

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Check if TELEPORT_TRUST_DOMAIN is set
if [ -z "$TELEPORT_TRUST_DOMAIN" ]; then
    echo "Error: TELEPORT_TRUST_DOMAIN is not set."
    echo "Please copy .env.example to .env and set your Teleport cluster domain."
    exit 1
fi

TRUST_DOMAIN="$TELEPORT_TRUST_DOMAIN"
NAMESPACE="sock-shop"

echo "What this script checks:"
echo "  Each sock-shop pod has an Istio sidecar (istio-proxy) holding a SPIFFE certificate."
echo "  In this demo, those certs are issued by Teleport (via tbot) instead of Istio's built-in CA."
echo ""
echo "  Expected SPIFFE ID: spiffe://<teleport-cluster-domain>/ns/<namespace>/sa/<service-account>"
echo "  Expected  = built from TELEPORT_TRUST_DOMAIN in .env + the pod's namespace and service account"
echo "  Actual    = extracted from the live Envoy config at localhost:15000/config_dump inside istio-proxy"
echo ""
echo "  A mismatch means the trust domain in the issued cert doesn't match your Teleport cluster."
echo "  Common causes: Istio was installed before configure-trust-domain.sh ran, or tbot is not running."
echo ""

for svc in front-end catalogue carts orders; do
  echo "=== Service: $svc ==="
  POD=$(kubectl get pod -n $NAMESPACE -l app=$svc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$POD" ]; then
    echo "❌ Pod not found for service $svc"
    echo ""
    continue
  fi

  # Get the service account
  SA=$(kubectl get pod -n $NAMESPACE $POD -o jsonpath='{.spec.serviceAccountName}')
  echo "Pod: $POD"
  echo "ServiceAccount: $SA"

  # Expected SPIFFE ID
  EXPECTED_SPIFFE="spiffe://$TRUST_DOMAIN/ns/$NAMESPACE/sa/$SA"
  echo "Expected SPIFFE ID: $EXPECTED_SPIFFE"

  # Get actual SPIFFE ID from Envoy config
  echo "  Running: kubectl exec -n $NAMESPACE $POD -c istio-proxy -- curl -s localhost:15000/config_dump"
  echo "  Fetching Envoy's live config dump from the istio-proxy sidecar, then grepping for a SPIFFE ID"
  echo "  matching this pod's namespace ($NAMESPACE) and service account ($SA)."
  ACTUAL_SPIFFE=$(kubectl exec -n $NAMESPACE $POD -c istio-proxy -- curl -s localhost:15000/config_dump 2>/dev/null | grep -o "spiffe://[^\"]*/$NAMESPACE/sa/$SA" | head -1)

  if [ -n "$ACTUAL_SPIFFE" ]; then
    echo "Actual SPIFFE ID:   $ACTUAL_SPIFFE"

    if [ "$EXPECTED_SPIFFE" = "$ACTUAL_SPIFFE" ]; then
      echo "✅ SPIFFE ID matches!"
    else
      echo "❌ SPIFFE ID mismatch!"
    fi
  else
    echo "⚠️  Could not retrieve actual SPIFFE ID from Envoy config"
  fi

  echo ""
done
