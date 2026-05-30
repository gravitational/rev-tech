#!/usr/bin/env bash
# Reads config.sh at the repo root and deploys all components.
# Prerequisites: kubectl, helm, openssl, tctl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

# ── Load config ───────────────────────────────────────────────────────────────
# shellcheck source=../config.sh
source "$ROOT_DIR/config.sh"

TELEPORT_VERSION="${TELEPORT_VERSION:-18.8.2}"
FB_VERSION="${FB_VERSION:-0.48.9}"
FLUENTD_VERSION="${FLUENTD_VERSION:-0.5.2}"

echo "Namespace: $NAMESPACE"
echo "Teleport : $TELEPORT_ADDRESS  (cluster: $CLUSTER_NAME)"
echo "Join     : $JOIN_METHOD"
echo "Output   : $OUTPUT_TYPE"
echo ""

# ── 1. Namespace + base resources ─────────────────────────────────────────────
echo "==> 1  Namespace + base resources"
# Generate a temp kustomization that injects the namespace into all resources.
KUST_TMP=$(mktemp -d)
cp "$ROOT_DIR/k8s"/*.yaml "$KUST_TMP/"
cat > "$KUST_TMP/kustomization.yaml" <<KEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $NAMESPACE
resources:
  - namespace.yaml
  - tbot-serviceaccount.yaml
  - haproxy-configmap.yaml
KEOF
kubectl apply -k "$KUST_TMP"
rm -rf "$KUST_TMP"

# ── 2. mTLS certs ─────────────────────────────────────────────────────────────
echo "==> 2  mTLS certs → fluent-bit-tls Secret"
NAMESPACE="$NAMESPACE" "$SCRIPT_DIR/generate-certs.sh"

# ── 2b. Resolve the tbot join token value (needed by step 3 and step 5).
#        token method  → auto-generated secret (printed for record-keeping)
#        all others    → the token resource name tbot-<BOT_NAME>
case "$JOIN_METHOD" in
  token)
    TBOT_TOKEN=$(openssl rand -hex 32)
    echo "Generated bot token: $TBOT_TOKEN"
    ;;
  *)
    TBOT_TOKEN="tbot-${BOT_NAME}"
    ;;
esac

# ── 2c. Bound keypair — must be generated BEFORE the token is created because
#        the public key is embedded directly in the token spec.
BOUND_PUBLIC_KEY=""
KEYPAIR_TMP=""
if [[ "$JOIN_METHOD" == "bound_keypair" ]]; then
  KEYPAIR_EXISTS=$(kubectl get secret tbot -n "$NAMESPACE" \
    -o jsonpath='{.data.id_bkp}' 2>/dev/null || true)

  if [[ -z "$KEYPAIR_EXISTS" ]]; then
    echo "==> 2b Generating bound keypair"
    KEYPAIR_TMP=$(mktemp -d)
    # Generates an Ed25519 keypair and writes id_bkp, id_bkp.pub,
    # and bkp_key_history.json to the storage directory.
    tbot keypair create \
      --proxy-server="$TELEPORT_ADDRESS" \
      --storage="file://${KEYPAIR_TMP}" \
      --overwrite 2>&1 | grep -v "^2026" || true
    BOUND_PUBLIC_KEY=$(cat "$KEYPAIR_TMP/id_bkp.pub")
    echo "Keypair generated."
  else
    echo "==> 2b Bound keypair already in tbot secret — reading existing public key"
    BOUND_PUBLIC_KEY=$(kubectl get secret tbot -n "$NAMESPACE" \
      -o jsonpath='{.data.id_bkp\.pub}' | base64 -d)
  fi
fi

# ── 3. Teleport resources (role, bot, join token) ─────────────────────────────
echo "==> 3  Teleport role, bot, and join token"
"$SCRIPT_DIR/generate-teleport-resources.sh" \
  "$JOIN_METHOD" "$CLUSTER_NAME" "$NAMESPACE" "$BOT_NAME" "${BOUND_PUBLIC_KEY:-$TBOT_TOKEN}" \
  | tctl create --force -f -

# Store all keypair files in the tbot storage secret now that the token exists.
if [[ -n "$KEYPAIR_TMP" ]]; then
  kubectl create secret generic tbot \
    --namespace "$NAMESPACE" \
    --from-file=id_bkp="${KEYPAIR_TMP}/id_bkp" \
    --from-file=id_bkp.pub="${KEYPAIR_TMP}/id_bkp.pub" \
    --from-file=bkp_key_history.json="${KEYPAIR_TMP}/bkp_key_history.json" \
    --dry-run=client -o yaml | kubectl apply -f -
  rm -rf "$KEYPAIR_TMP"
  echo "Keypair stored in tbot secret."
fi

# ── 4. Output ─────────────────────────────────────────────────────────────────
helm repo add fluent https://fluent.github.io/helm-charts --force-update
helm repo add teleport https://charts.releases.teleport.dev --force-update

case "$OUTPUT_TYPE" in
  fluent-bit)
    echo "==> 4  Fluent Bit"
    helm upgrade --install fluent-bit fluent/fluent-bit \
      --namespace "$NAMESPACE" \
      --version "$FB_VERSION" \
      -f "$ROOT_DIR/helm/fluent-bit/values.yaml" \
      --wait
    # The chart's Service only exposes port 2020; patch in 8888 for HAProxy.
    kubectl patch service fluent-bit -n "$NAMESPACE" \
      --type=json \
      -p='[{"op":"add","path":"/spec/ports/-","value":{"name":"https","port":8888,"targetPort":8888,"protocol":"TCP"}}]'
    FLUENTD_URL="https://fluent-bit.$NAMESPACE.svc.cluster.local:8888/teleport.events"
    FLUENTD_SESSION_URL="https://fluent-bit.$NAMESPACE.svc.cluster.local:8888/teleport.session.logs"
    ;;

  fluentd)
    echo "==> 4  Fluentd"
    helm upgrade --install fluentd fluent/fluentd \
      --namespace "$NAMESPACE" \
      --version "$FLUENTD_VERSION" \
      -f "$ROOT_DIR/helm/fluentd/values.yaml" \
      --wait
    FLUENTD_URL="https://fluentd.$NAMESPACE.svc.cluster.local:8888/teleport.events"
    FLUENTD_SESSION_URL="https://fluentd.$NAMESPACE.svc.cluster.local:8888/teleport.session.logs"
    ;;

  none)
    echo "==> 4  No output chart (using custom endpoint from config.sh)"
    if [[ -z "${FLUENTD_URL:-}" ]]; then
      echo "ERROR: OUTPUT_TYPE=none but FLUENTD_URL is not set in config.sh" >&2
      exit 1
    fi
    FLUENTD_SESSION_URL="${FLUENTD_SESSION_URL:-}"
    ;;

  *)
    echo "ERROR: Unknown OUTPUT_TYPE '$OUTPUT_TYPE'. Use: fluent-bit | fluentd | none" >&2
    exit 1
    ;;
esac

# ── 5. tbot ───────────────────────────────────────────────────────────────────
echo "==> 5  tbot (Machine ID)"

# bound_keypair must persist its keypair state across pod restarts.
TBOT_STORAGE_TYPE="memory"
[[ "$JOIN_METHOD" == "bound_keypair" ]] && TBOT_STORAGE_TYPE="kubernetes_secret"

helm upgrade --install tbot teleport/tbot \
  --namespace "$NAMESPACE" \
  --version "$TELEPORT_VERSION" \
  -f "$ROOT_DIR/helm/tbot/values.yaml" \
  --set teleportProxyAddress="$TELEPORT_ADDRESS" \
  --set clusterName="$CLUSTER_NAME" \
  --set joinMethod="$JOIN_METHOD" \
  --set token="$TBOT_TOKEN" \
  --set storage.destination.type="$TBOT_STORAGE_TYPE" \
  --wait

# ── 6. Event-handler ──────────────────────────────────────────────────────────
echo "==> 6  Event-handler"
helm upgrade --install event-handler teleport/teleport-plugin-event-handler \
  --namespace "$NAMESPACE" \
  --version "$TELEPORT_VERSION" \
  -f "$ROOT_DIR/helm/event-handler/values.yaml" \
  --set teleport.address="$TELEPORT_ADDRESS" \
  --set fluentd.url="$FLUENTD_URL" \
  --set fluentd.sessionUrl="$FLUENTD_SESSION_URL" \
  --wait

echo ""
echo "Done. Useful commands:"
echo "  kubectl get pods -n $NAMESPACE"
case "$OUTPUT_TYPE" in
  fluent-bit)
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=fluent-bit -c fluent-bit -f" ;;
  fluentd)
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=fluentd -f" ;;
esac
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=teleport-plugin-event-handler -f"
