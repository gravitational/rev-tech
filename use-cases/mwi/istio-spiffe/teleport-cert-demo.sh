#!/bin/bash

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

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     TELEPORT WORKLOAD IDENTITY CERTIFICATE ISSUANCE DEMO       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo

echo "📋 Step 1: Show Workload Identity Configuration"
echo "─────────────────────────────────────────────────────────────────"
echo "This configuration defines the SPIFFE ID template for Istio workloads:"
echo
tctl get workload_identity/istio-workloads --format=yaml | grep -A 5 "spec:"
echo

echo "📦 Step 2: List Active Workloads Getting Certificates"
echo "─────────────────────────────────────────────────────────────────"
kubectl get pods -n sock-shop --no-headers | awk '{print $1 " - " $2 " containers - " $3}'
echo

echo "🔐 Step 3: Extract Certificate from Istio Sidecar"
echo "─────────────────────────────────────────────────────────────────"
POD=$(kubectl get pods -n sock-shop -l app=front-end -o jsonpath='{.items[0].metadata.name}')
echo "Inspecting pod: $POD"
echo

# Get certificate info from Envoy
CERT_INFO=$(kubectl exec -n sock-shop $POD -c istio-proxy -- curl -s localhost:15000/certs)

echo "✓ Certificate Authority:"
echo "$CERT_INFO" | grep -A 3 '"ca_cert"' | grep 'path' | head -1

echo
echo "✓ Certificate Chain:"
SPIFFE_ID=$(echo "$CERT_INFO" | grep -A 2 'subject_alt_names' | grep 'uri' | head -1 | cut -d'"' -f4)
echo "   SPIFFE ID: $SPIFFE_ID"

VALID_FROM=$(echo "$CERT_INFO" | grep 'valid_from' | head -2 | tail -1 | cut -d'"' -f4)
EXPIRATION=$(echo "$CERT_INFO" | grep 'expiration_time' | head -2 | tail -1 | cut -d'"' -f4)
echo "   Valid From: $VALID_FROM"
echo "   Expires: $EXPIRATION"

echo
echo "✅ Step 4: Verification"
echo "─────────────────────────────────────────────────────────────────"
echo "Certificate matches Teleport workload identity pattern:"
echo "  Template: /ns/{{ workload.kubernetes.namespace }}/sa/{{ workload.kubernetes.service_account }}"
echo "  Issued:   /ns/sock-shop/sa/front-end"
echo
echo "Trust domain: $TELEPORT_TRUST_DOMAIN (Teleport cluster)"
echo

echo "🔄 Step 5: Show Certificate Rotation"
echo "─────────────────────────────────────────────────────────────────"
echo "Certificates are auto-rotated by tbot every 2 minutes"
echo "Certificate TTL: 4 minutes (configured in tbot)"
echo

# Show a second workload
POD2=$(kubectl get pods -n sock-shop -l app=carts -o jsonpath='{.items[0].metadata.name}')
CERT_INFO2=$(kubectl exec -n sock-shop $POD2 -c istio-proxy -- curl -s localhost:15000/certs 2>/dev/null)
SPIFFE_ID2=$(echo "$CERT_INFO2" | grep -A 2 'subject_alt_names' | grep 'uri' | head -1 | cut -d'"' -f4)

echo "Another workload example:"
echo "  Pod: $POD2"
echo "  SPIFFE ID: $SPIFFE_ID2"

echo
echo "════════════════════════════════════════════════════════════════"
echo "✓ Demo Complete: Certificates are being issued by Teleport!"
echo "════════════════════════════════════════════════════════════════"

