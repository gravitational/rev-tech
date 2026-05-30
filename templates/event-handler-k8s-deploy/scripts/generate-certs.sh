#!/usr/bin/env bash
# Generates a CA, a Fluent Bit server cert, and a client cert for the event-handler,
# then loads them into Kubernetes as the 'fluent-bit-tls' Secret.
set -euo pipefail

NAMESPACE="${NAMESPACE:-teleport-events}"
CERTS_DIR="$(cd "$(dirname "$0")/.." && pwd)/certs"
mkdir -p "$CERTS_DIR"

echo "==> Generating CA"
openssl genrsa -out "$CERTS_DIR/ca.key" 4096
openssl req -new -x509 -days 3650 -key "$CERTS_DIR/ca.key" \
  -out "$CERTS_DIR/ca.crt" \
  -subj "/CN=teleport-fluentbit-ca"

echo "==> Generating server cert (covers fluent-bit and fluentd service names)"
openssl genrsa -out "$CERTS_DIR/server.key" 4096
openssl req -new -key "$CERTS_DIR/server.key" \
  -out "$CERTS_DIR/server.csr" \
  -subj "/CN=fluent-bit"
openssl x509 -req -days 3650 \
  -in "$CERTS_DIR/server.csr" \
  -CA "$CERTS_DIR/ca.crt" \
  -CAkey "$CERTS_DIR/ca.key" \
  -CAcreateserial \
  -out "$CERTS_DIR/server.crt" \
  -extfile <(printf "subjectAltName=DNS:fluent-bit,DNS:fluent-bit.%s.svc.cluster.local,DNS:fluentd,DNS:fluentd.%s.svc.cluster.local,DNS:localhost,IP:127.0.0.1" "$NAMESPACE" "$NAMESPACE")

echo "==> Generating event-handler client cert"
openssl genrsa -out "$CERTS_DIR/client.key" 4096
openssl req -new -key "$CERTS_DIR/client.key" \
  -out "$CERTS_DIR/client.csr" \
  -subj "/CN=teleport-event-handler"
openssl x509 -req -days 3650 \
  -in "$CERTS_DIR/client.csr" \
  -CA "$CERTS_DIR/ca.crt" \
  -CAkey "$CERTS_DIR/ca.key" \
  -CAcreateserial \
  -out "$CERTS_DIR/client.crt"

rm -f "$CERTS_DIR"/*.csr "$CERTS_DIR"/*.srl

# HAProxy requires cert + key in a single PEM file.
cat "$CERTS_DIR/server.crt" "$CERTS_DIR/server.key" > "$CERTS_DIR/server.pem"

echo "==> Creating Kubernetes Secret 'fluent-bit-tls' in namespace $NAMESPACE"
kubectl create secret generic fluent-bit-tls \
  --namespace "$NAMESPACE" \
  --from-file=ca.crt="$CERTS_DIR/ca.crt" \
  --from-file=server.crt="$CERTS_DIR/server.crt" \
  --from-file=server.key="$CERTS_DIR/server.key" \
  --from-file=server.pem="$CERTS_DIR/server.pem" \
  --from-file=client.crt="$CERTS_DIR/client.crt" \
  --from-file=client.key="$CERTS_DIR/client.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done. Certs in $CERTS_DIR"
