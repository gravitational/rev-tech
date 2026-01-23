#!/bin/bash

# Validate SPIFFE IDs for sock-shop services

TRUST_DOMAIN="ellinj.teleport.sh"
NAMESPACE="sock-shop"

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
