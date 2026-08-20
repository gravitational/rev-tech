#!/usr/bin/env bash
# Reverses setup.sh: uninstalls every Helm release this demo created,
# deletes the Kubernetes secrets/namespace, and removes the Teleport
# resources. Best-effort -- a resource that's already gone (partial
# previous run, manual cleanup, etc.) doesn't fail the script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

YES=false
KEEP_NAMESPACE=false
for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=true ;;
    --keep-namespace) KEEP_NAMESPACE=true ;;
    *) die "Unknown argument: $arg (supported: -y/--yes, --keep-namespace)" ;;
  esac
done

[[ -f .env ]] || die ".env not found -- nothing to tear down (or you're in the wrong directory)."
set -a
# shellcheck disable=SC1091
source .env
set +a

for var in NAMESPACE WORKLOAD_IDENTITY_NAME BOT_NAME APP_NAME CLI_ROLE_NAME \
           SPIFFE_CA_SECRET_NAME DB_CLIENT_CA_SECRET_NAME TELEPORT_AGENT_RELEASE SUFFIX; do
  [[ -n "${!var:-}" ]] || die "$var is not set in .env."
done

echo "This will delete, in namespace \"$NAMESPACE\":"
echo "  - Helm releases: pg-client-python-$SUFFIX, pg-client-go-$SUFFIX, $BOT_NAME, $TELEPORT_AGENT_RELEASE, postgres-$SUFFIX"
echo "  - Secrets: $SPIFFE_CA_SECRET_NAME, $DB_CLIENT_CA_SECRET_NAME"
if [[ "$KEEP_NAMESPACE" == "false" ]]; then
  echo "  - The \"$NAMESPACE\" namespace itself (including its PVCs -- the demo data)"
fi
echo "And these Teleport resources: workload_identity/$WORKLOAD_IDENTITY_NAME," \
     "role/$BOT_NAME, bot/$BOT_NAME, role/$CLI_ROLE_NAME, role/${CLI_ROLE_NAME}-db-access"

if [[ "$YES" != "true" ]]; then
  read -r -p "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

log "Uninstalling Helm releases"
for release in "pg-client-python-$SUFFIX" "pg-client-go-$SUFFIX" "$BOT_NAME" "$TELEPORT_AGENT_RELEASE" "postgres-$SUFFIX"; do
  if helm status "$release" -n "$NAMESPACE" >/dev/null 2>&1; then
    helm uninstall "$release" -n "$NAMESPACE"
  else
    info "$release: not installed, skipping"
  fi
done

log "Deleting Kubernetes secrets created outside Helm"
kubectl delete secret "$SPIFFE_CA_SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
kubectl delete secret "$DB_CLIENT_CA_SECRET_NAME" -n "$NAMESPACE" --ignore-not-found

if [[ "$KEEP_NAMESPACE" == "false" ]]; then
  log "Deleting namespace \"$NAMESPACE\""
  kubectl delete namespace "$NAMESPACE" --ignore-not-found
else
  info "Skipping namespace deletion (--keep-namespace)"
fi

log "Removing Teleport resources"
for resource in \
  "workload_identity/$WORKLOAD_IDENTITY_NAME" \
  "role/$BOT_NAME" \
  "bot/$BOT_NAME" \
  "role/$CLI_ROLE_NAME" \
  "role/${CLI_ROLE_NAME}-db-access"
do
  if tctl rm "$resource" >/dev/null 2>&1; then
    info "removed $resource"
  else
    info "$resource: not found, skipping"
  fi
done

echo
echo "Note: this does not revoke any join token still outstanding from a"
echo "prior 'tctl tokens add' (they expire on their own -- see JOIN_TOKEN_TTL"
echo "in .env). If you set DEPLOY_TELEPORT_AGENT=false and merged"
echo "teleport/app-service-teleport-config.yaml / db-service-teleport-config.yaml"
echo "into an agent you run elsewhere, remove those blocks from it yourself --"
echo "uninstalling \"$TELEPORT_AGENT_RELEASE\" above only covers the agent"
echo "setup.sh deploys."
echo
echo "Done."
