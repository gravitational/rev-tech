#!/usr/bin/env bash
# conference-preflight.sh — verify an event booth environment (built from
# profiles/presets/conference.tfvars) as the SSO (SE) user.
#
# Run with an active SSO session on the event cluster. Checks the whole booth
# environment in ~30s: roles, resources, labels, the auto-approve rule (live
# end-to-end, self-cleaning), DB connectivity, MCP allowlist + tools/list
# probe, desktop registration, and stale locks from rehearsals.
#
#   PROXY=<event-cluster> ./conference-preflight.sh    # full run (includes a real request cycle)
#   SKIP_REQUEST_TEST=1 PROXY=... ./conference-preflight.sh   # read-only checks only
#   TELEPORT_AUTH_NS=<ns> enables in-pod tctl cleanup of the test request
#   (self-hosted control planes in k8s only; otherwise the request just expires)
#
# Exit code = number of failed checks. WARNs don't fail the run.

set -uo pipefail

PROXY="${PROXY:?usage: PROXY=<event-cluster> [DEMO_USER=<persona>] $0}"
DEMO_USER="${DEMO_USER:-bob}"
PASS=0; FAIL=0; WARN=0

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'; else G=""; R=""; Y=""; N=""; fi
ok()   { echo "${G}PASS${N}  $1"; PASS=$((PASS+1)); }
bad()  { echo "${R}FAIL${N}  $1"; FAIL=$((FAIL+1)); }
warn() { echo "${Y}WARN${N}  $1"; WARN=$((WARN+1)); }

echo "── booth pre-flight: $PROXY ($(date '+%H:%M')) ────────────────────"

# 1. Session: logged in, right proxy, SE roles present
STATUS=$(tsh status 2>/dev/null)
if ! grep -q "$PROXY" <<<"$STATUS"; then
  bad "not logged into $PROXY — run: tsh login --proxy=$PROXY"
  echo "aborting: everything else needs a session"; exit 1
fi
ok "logged into $PROXY ($(grep 'Logged in as:' <<<"$STATUS" | awk '{print $4}'))"
for role in dev-access demo-requester demo-reviewer; do
  grep -q "$role" <<<"$STATUS" && ok "cert carries $role" \
    || bad "cert missing $role — re-login (roles apply at login) or check connector mapping"
done

# 2. Cluster: Okta is the default auth
AUTHTYPE=$(curl -s --max-time 5 "https://$PROXY/webapi/ping" | jq -r '.auth.type' 2>/dev/null)
[ "$AUTHTYPE" = "saml" ] && ok "default login is Okta (auth.type=saml)" \
  || bad "auth.type=$AUTHTYPE — expected saml; check gitops values"

# 3. SSH nodes present with healthy dynamic labels
NODES=$(tsh ls 2>/dev/null)
for n in dev-ssh-0 dev-ssh-1 prod-ssh-0; do
  grep -q "^$n " <<<"$NODES" && ok "node $n online" || bad "node $n missing from tsh ls"
done
BADLBL=$(grep -cE 'disk_used=exit|disk_used=$' <<<"$NODES" || true)
[ "$BADLBL" -eq 0 ] && ok "dynamic labels healthy (disk_used numeric)" \
  || bad "$BADLBL node(s) show broken disk_used label"

# 4. Database registered + live connect as writer
tsh db ls 2>/dev/null | grep -q postgres-dev && ok "postgres-dev registered" || bad "postgres-dev missing"
DB_OUT=$(echo "SELECT 1;" | tsh db connect postgres-dev --db-user=writer --db-name=postgres 2>&1)
grep -q "(1 row)" <<<"$DB_OUT" && ok "live psql connect as writer works" \
  || bad "db connect failed: $(tail -1 <<<"$DB_OUT")"

# 5. Apps registered (JSON — the table output truncates names)
APPS=$(tsh apps ls --format=json 2>/dev/null | jq -r '.[].metadata.name')
for app in demo-panel-dev grafana-dev mcp-filesystem-dev; do
  grep -qx "$app" <<<"$APPS" && ok "$app registered" || bad "$app missing"
done

# 5a. Each app must be served by exactly its own host. A broad app_service
# selector on any host claims other apps too, and the proxy then routes
# sessions to hosts whose upstreams don't exist (intermittent Connection
# Refused — burned us 2026-07-24).
PAIRS=$(tctl apps ls --format=json 2>/dev/null | jq -r '[.[] | select(.metadata.name | test("demo-panel-dev|grafana-dev|mcp-filesystem-dev")) | .metadata.name + ":" + (.spec.hostname // "?")] | sort | join(" ")')
if [ "$PAIRS" = "demo-panel-dev:dev-demo-panel grafana-dev:dev-grafana mcp-filesystem-dev:dev-mcp-filesystem" ]; then
  ok "each app served by exactly its own host"
else
  bad "app-server claims wrong (expect one server per app): $PAIRS"
fi

# 5b. Per-app subdomain DNS — browser App Access needs the wildcard record
if [ -n "$(dig +short "demo-panel-dev.$PROXY" 2>/dev/null)" ]; then
  ok "app subdomain DNS resolves (wildcard record present)"
else
  bad "demo-panel-dev.$PROXY does not resolve — wildcard *.$PROXY DNS record missing; browser App Access (Section 5) will fail"
fi

# 6. Windows desktop registered (singular kind — plural errors)
DESKTOP=$(tctl get windows_desktop --format=json 2>/dev/null | jq -r '.[].metadata.name' | head -1)
[ -n "$DESKTOP" ] && ok "windows desktop registered: $DESKTOP" || bad "no windows_desktop registered"

# 7. Demo RBAC objects all present
ROLES=$(tctl get roles --format=json 2>/dev/null | jq -r '.[].metadata.name')
for role in dev-access staging-access prod-access prod-access-mfa demo-requester demo-reviewer; do
  grep -qx "$role" <<<"$ROLES" && ok "role $role exists" || bad "role $role missing"
done
for u in bob alice; do
  tctl get "user/$u" >/dev/null 2>&1 && ok "persona $u exists" || bad "persona $u missing"
done

# 8. MCP read-only allowlist still on dev-access
MCP_TOOLS=$(tctl get role/dev-access --format=json 2>/dev/null | jq -c '.[0].spec.allow.mcp.tools')
if [ "$MCP_TOOLS" = '["read_*","list_*","search_files","get_file_info","directory_tree"]' ]; then
  ok "dev-access MCP allowlist is read-only"
else
  bad "dev-access MCP tools = $MCP_TOOLS — Inspector contrast beat will not fire"
fi

# 8a. Inspector contrast beat: rw role exists and the SE cert carries it.
# Teleport filters denied tools out of tools/list, so the demo is List Tools
# as SE (full toolset via mcp-filesystem-rw) vs as bob (read-only allowlist).
RW_TOOLS=$(tctl get role/mcp-filesystem-rw --format=json 2>/dev/null | jq -c '.[0].spec.allow.mcp.tools')
[ "$RW_TOOLS" = '["*"]' ] && ok "mcp-filesystem-rw role present (all tools)" \
  || bad "mcp-filesystem-rw role missing or wrong (tools=$RW_TOOLS)"
grep -q "mcp-filesystem-rw" <<<"$STATUS" && ok "cert carries mcp-filesystem-rw (SE side of the contrast)" \
  || bad "cert missing mcp-filesystem-rw — add it to the okta connector mapping (gitops) and re-login; until then SEs see the same read-only list as bob"

# 8b. Live MCP probe: drive a real stdio session and check what tools/list
# actually offers this cert. Expectation flips with the rw role.
MCP_LIST=$({ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"preflight","version":"1.0"}}}'; sleep 4; printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'; sleep 4; } | tsh mcp connect mcp-filesystem-dev 2>/dev/null | jq -r 'select(.id==2) | [.result.tools[].name] | join(",")')
if [ -z "$MCP_LIST" ]; then
  bad "MCP live probe returned no tools — session failed (check dev-mcp-filesystem / docker)"
elif grep -q "mcp-filesystem-rw" <<<"$STATUS"; then
  grep -q "write_file" <<<"$MCP_LIST" && ok "MCP probe: full toolset offered (rw cert)" \
    || bad "MCP probe: rw role on cert but write_file not offered: $MCP_LIST"
else
  grep -q "write_file" <<<"$MCP_LIST" && bad "MCP probe: write_file offered WITHOUT the rw role: $MCP_LIST" \
    || ok "MCP probe: read-only filtering enforced (write_file absent from tools/list)"
fi

# 9. Auto-approve rule exists + AI summary model configured
tctl get access_monitoring_rule/demo-auto-approve-staging >/dev/null 2>&1 \
  && ok "auto-approve rule present" || bad "access_monitoring_rule demo-auto-approve-staging missing"
tctl get inference_model --format=json 2>/dev/null | jq -r '.[].metadata.name' | grep -q bedrock \
  && ok "AI session-summary model configured" || warn "no inference_model found — AI summary beat unavailable"

# 10. No stale locks on the personas (left over from lock-beat rehearsals)
LOCKS=$(tctl get locks --format=json 2>/dev/null | jq -r '.[].spec.target.user // empty')
if grep -qE "^(bob|alice)$" <<<"$LOCKS"; then
  bad "stale lock on a demo persona — tctl get locks, then tctl rm lock/<name>"
else
  ok "no stale locks on demo personas"
fi

# 11. Live auto-approval cycle (creates a real request as $DEMO_USER, then deletes it)
if [ "${SKIP_REQUEST_TEST:-0}" != "1" ]; then
  REQ=$(tctl request create "$DEMO_USER" --roles=staging-access --reason="authorized job" 2>/dev/null)
  if [ -z "$REQ" ]; then
    bad "could not create test request as $DEMO_USER"
  else
    STATE=""
    for _ in 1 2 3 4 5 6; do
      sleep 3
      # tsh request show works for reviewers; tctl request ls is scoped and shows nothing
      STATE=$(tsh request show "$REQ" 2>/dev/null | awk '/^Status:/ {print $2}')
      [ "$STATE" = "APPROVED" ] && break
    done
    [ "$STATE" = "APPROVED" ] && ok "auto-approval fired (request $REQ APPROVED)" \
      || bad "auto-approval did not fire within 18s (state: ${STATE:-not visible})"
    # Deleting requests needs local-admin tctl: exec into the auth pod if the
    # control plane is self-hosted in k8s (set TELEPORT_AUTH_NS to enable).
    if [ -n "${TELEPORT_AUTH_NS:-}" ]; then
      tsh kube login "$PROXY" >/dev/null 2>&1
      AUTHPOD=$(tsh kubectl get pods -n "$TELEPORT_AUTH_NS" -l app.kubernetes.io/component=auth -o name 2>/dev/null | head -1)
      if [ -n "$AUTHPOD" ] && tsh kubectl exec -n "$TELEPORT_AUTH_NS" "${AUTHPOD#pod/}" -- tctl request rm --force "$REQ" >/dev/null 2>&1; then
        ok "test request cleaned up"
      else
        warn "could not delete test request $REQ — it expires on its own, but remove via in-pod tctl for a clean Access Requests view"
      fi
    else
      warn "test request $REQ left to expire (set TELEPORT_AUTH_NS for in-pod tctl cleanup)"
    fi
  fi
else
  warn "request cycle skipped (SKIP_REQUEST_TEST=1)"
fi

echo "───────────────────────────────────────────────────────────────"
echo "  $PASS passed, $FAIL failed, $WARN warnings"
[ "$FAIL" -eq 0 ] && echo "  Booth is GO." || echo "  Fix the FAILs before the first demo."
exit "$FAIL"
