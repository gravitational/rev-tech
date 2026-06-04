#!/usr/bin/env bash
# Removes everything created by deploy.sh.
# Reads config.sh for namespace and output type.
# Prerequisites: kubectl, helm, tctl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

# shellcheck source=../config.sh
source "$ROOT_DIR/config.sh"

echo "Namespace: $NAMESPACE"
echo "Output   : $OUTPUT_TYPE"
echo ""
echo "This will permanently delete:"
echo "  • All Helm releases in namespace '$NAMESPACE'"
echo "  • The '$NAMESPACE' namespace and everything in it"
echo "  • Teleport: token/tbot-${BOT_NAME}"
echo "  • Teleport: bot/${BOT_NAME}"
echo "  • Teleport: user/bot-${BOT_NAME}  (auto-created by the bot)"
echo "  • Teleport: role/${BOT_NAME}"
echo ""
read -rp "Type the namespace name to confirm: " confirm
[[ "$confirm" == "$NAMESPACE" ]] || { echo "Aborted — input did not match '$NAMESPACE'."; exit 0; }

# ── Helm releases ──────────────────────────────────────────────────────────────
echo "==> Helm releases"
helm uninstall event-handler  --namespace "$NAMESPACE" --ignore-not-found 2>/dev/null || true
helm uninstall tbot            --namespace "$NAMESPACE" --ignore-not-found 2>/dev/null || true

case "$OUTPUT_TYPE" in
  fluent-bit) helm uninstall fluent-bit --namespace "$NAMESPACE" --ignore-not-found 2>/dev/null || true ;;
  fluentd)    helm uninstall fluentd    --namespace "$NAMESPACE" --ignore-not-found 2>/dev/null || true ;;
esac

# ── Raw k8s resources ──────────────────────────────────────────────────────────
echo "==> Kubernetes resources"
kubectl delete secret   fluent-bit-tls     -n "$NAMESPACE" --ignore-not-found
kubectl delete secret   teleport-identity  -n "$NAMESPACE" --ignore-not-found
kubectl delete secret   tbot               -n "$NAMESPACE" --ignore-not-found
kubectl delete secret   tbot-out           -n "$NAMESPACE" --ignore-not-found
kubectl delete configmap haproxy-config    -n "$NAMESPACE" --ignore-not-found
kubectl delete serviceaccount tbot         -n "$NAMESPACE" --ignore-not-found

# ── Namespace (last — waits for all resources to terminate first) ──────────────
echo "==> Namespace"
kubectl delete namespace "$NAMESPACE" --ignore-not-found

# ── Teleport cluster resources ─────────────────────────────────────────────────
echo "==> Teleport resources"
# Delete token first so tbot cannot re-join during teardown.
tctl rm "token/tbot-${BOT_NAME}"  2>/dev/null || true
# Deleting the bot also revokes its certificates, but the user it created
# (bot-<name>) must be removed explicitly.
tctl rm "bot/${BOT_NAME}"         2>/dev/null || true
tctl rm "user/bot-${BOT_NAME}"    2>/dev/null || true
tctl rm "role/${BOT_NAME}"        2>/dev/null || true
# Remove any registered bound keypairs for this bot.
tctl bots keypairs rm "$BOT_NAME" 2>/dev/null || true

# ── Local cert files ───────────────────────────────────────────────────────────
read -rp "Delete local cert files in certs/? [y/N] " confirm_certs
if [[ "$confirm_certs" == "y" || "$confirm_certs" == "Y" ]]; then
  rm -rf "$ROOT_DIR/certs"
  echo "Certs deleted."
fi

echo ""
echo "Done."
