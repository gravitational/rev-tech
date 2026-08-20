#!/usr/bin/env bash
# Sets up the Postgres + Teleport Workload Identity demo end to end:
# applies the Teleport-side resources in teleport/, fetches the trust
# material Postgres needs, and deploys postgres-chart + tbot-chart (and
# the Python/Go client CronJobs, each running one transaction every two
# minutes).
#
# Idempotent: safe to re-run after editing .env. Toggling
# ENABLE_DB_SERVICE from true to false and re-running removes the
# Database Access resources it previously created; see teardown.sh to
# remove everything.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./setup.sh [--dry-run] [--debug] [-h|--help]

  --dry-run  Don't create/change anything. Every `helm upgrade --install`
             runs with Helm's own --dry-run (renders and validates
             without installing); every tctl/kubectl/tsh/docker mutation
             is skipped and printed instead of run.
  --debug    Verbose: `set -x`, plus Helm's own --debug on every Helm
             call (most useful combined with --dry-run, to see the
             fully rendered manifests).
USAGE
}

DRY_RUN=false
DEBUG=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --debug) DEBUG=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
done
[[ "$DEBUG" == "true" ]] && set -x

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------
# All to stderr, on purpose: several helpers below (generate_join_token,
# render_template via apply_teleport_resource) are invoked through
# command substitution ($(...)) to capture a real return value. Any of
# these writing to stdout would get silently concatenated into that
# captured value -- including the ANSI color codes, which downstream
# YAML parsers reject as invalid control characters. Terminal display is
# unaffected either way (stderr shows up in your terminal same as
# stdout); this only matters for output that gets captured.
log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1" >&2; }
info() { printf '    %s\n' "$1" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }
dryrun_info() { printf '    \033[2m[dry-run] would: %s\033[0m\n' "$1" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not on PATH."
}

# Renders a ${VAR}-style template using the current environment.
# python3's string.Template is used (not envsubst) so this doesn't
# depend on gettext being installed.
render_template() {
  local src="$1"
  python3 - "$src" <<'PY'
import os, sys, string
with open(sys.argv[1]) as f:
    tmpl = string.Template(f.read())
sys.stdout.write(tmpl.safe_substitute(os.environ))
PY
}

# Idempotent create-or-update for a Teleport resource rendered from a
# template file. In --dry-run, prints the rendered resource instead of
# applying it.
apply_teleport_resource() {
  local template="$1"
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  render_template "$template" > "$tmp"
  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun_info "tctl create -f $template, rendered as:"
    sed 's/^/          /' "$tmp"
    return 0
  fi
  tctl create -f "$tmp"
}

# Best-effort removal -- never fails the script if the resource is
# already gone.
remove_teleport_resource() {
  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun_info "tctl rm $1"
    return 0
  fi
  tctl rm "$1" >/dev/null 2>&1 || true
}

# Idempotent create-or-update for a generic-literal Kubernetes secret.
# Usage: upsert_secret_from_file <secret-name> <key-in-secret> <path-to-file>
upsert_secret_from_file() {
  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun_info "upsert Secret/$1 (key \"$2\") from $3"
    return 0
  fi
  kubectl create secret generic "$1" \
    --from-file="$2=$3" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# Creates a `kind: token` resource for the plain `token` join method
# with a fresh random name and echoes that name on stdout -- for this
# join method, the resource's own name IS the secret a caller presents
# to join (confirmed against a live cluster; there is no `tctl tokens
# add` equivalent that can bind a token to a specific bot name or set
# `spec.roles` to anything other than its flat --type list, so a
# `tctl create -f` of the resource directly is the only way).
#
# Usage: generate_join_token <ttl> "<roles as a YAML flow list>" [bot_name]
#   generate_join_token "4h" "[Bot]" "postgres-wi-tbot"
#   generate_join_token "4h" "[App, Db]"
#
# In --dry-run, doesn't mint a real token -- prints what would be
# created and echoes a placeholder so downstream `helm --dry-run` calls
# still have a string to render with.
generate_join_token() {
  local ttl="$1" roles="$2" bot_name="${3:-}"
  local token_value expiry tmp

  read -r token_value expiry <<<"$(python3 -c '
import datetime, re, secrets, sys
m = re.fullmatch(r"(\d+)(h|m|s)", sys.argv[1])
if not m:
    sys.exit("unsupported TTL format (expected e.g. 4h/30m/90s): " + sys.argv[1])
n, unit = int(m.group(1)), m.group(2)
seconds = n * {"h": 3600, "m": 60, "s": 1}[unit]
expiry = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=seconds)
print(secrets.token_hex(24), expiry.strftime("%Y-%m-%dT%H:%M:%SZ"))
' "$ttl")"
  [[ -n "$token_value" && -n "$expiry" ]] || return 1

  tmp="$(mktemp)"
  {
    echo "kind: token"
    echo "version: v2"
    echo "metadata:"
    echo "  name: $token_value"
    echo "  expires: \"$expiry\""
    echo "spec:"
    echo "  join_method: token"
    echo "  roles: $roles"
    [[ -n "$bot_name" ]] && echo "  bot_name: $bot_name"
  } > "$tmp"

  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun_info "tctl create -f <generated join token>, rendered as:"
    sed 's/^/          /' "$tmp" >&2
    rm -f "$tmp"
    printf 'dry-run-placeholder-token'
    return 0
  fi

  # tctl's own success message for this resource type is literally
  # `provision_token "<token value>" has been created` -- for the plain
  # `token` join method, the resource name IS the bearer secret, so that
  # confirmation message would print the token to the terminal (and any
  # scrollback/CI log) even though it's never captured by the `$(...)`
  # around this function. Discard stdout entirely; a real failure still
  # surfaces via tctl's own stderr output and this function's `return 1`.
  if ! tctl create -f "$tmp" >/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  printf '%s' "$token_value"
}

# `helm upgrade --install`, with $HELM_FLAGS (--dry-run/--debug, set up
# after .env loads) appended. In --dry-run, a chart that legitimately
# depends on a Secret an earlier (also dry-run, therefore skipped) step
# would have created for real is expected to fail its render -- that's
# reported as informational rather than aborting the rest of the
# preview.
helm_install() {
  local release="$1" chart="$2"
  shift 2
  if helm upgrade --install "$release" "$chart" --namespace "$NAMESPACE" "$@" "${HELM_FLAGS[@]}"; then
    return 0
  elif [[ "$DRY_RUN" == "true" ]]; then
    info "(dry-run couldn't fully render $release -- it likely depends on a Secret/resource an earlier step would have created for real; expected when previewing a from-scratch install)"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------
if [[ ! -f .env ]]; then
  die ".env not found. Run: cp .env.example .env, fill in TELEPORT_PROXY_ADDR, then re-run."
fi

# Every resource/release name below is built from ${SUFFIX} (see
# .env.example) so this demo can be installed more than once against
# the same Teleport cluster/Kubernetes cluster without colliding.
# Generated once on first run and persisted into .env -- NOT just
# exported into this process's environment -- so that later lines in
# .env referencing ${SUFFIX} (NAMESPACE=postgres-wi-demo-${SUFFIX},
# etc.) actually pick it up when `source`d below, and so re-runs (and
# teardown.sh) keep reusing the same names instead of orphaning this
# run's resources.
ENV_FILE=".env"
if ! grep -qE '^SUFFIX=[^[:space:]]+' .env; then
  GENERATED_SUFFIX="$(python3 -c 'import random, string; print("".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(4)))')"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "SUFFIX not set in .env -- previewing with a throwaway suffix ($GENERATED_SUFFIX); a real run will generate and save its own."
    ENV_FILE="$(mktemp)"
    cp .env "$ENV_FILE"
  else
    log "No SUFFIX in .env yet -- generating one ($GENERATED_SUFFIX) and saving it to .env"
  fi
  if grep -qE '^SUFFIX=' "$ENV_FILE"; then
    sed -i.bak "s/^SUFFIX=.*/SUFFIX=$GENERATED_SUFFIX/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    { echo "SUFFIX=$GENERATED_SUFFIX"; cat "$ENV_FILE"; } > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  fi
fi
set -a
# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"
set +a
[[ "$ENV_FILE" != ".env" ]] && rm -f "$ENV_FILE"

for var in TELEPORT_PROXY_ADDR NAMESPACE WORKLOAD_IDENTITY_NAME POSTGRES_DB_USER \
           BOT_NAME APP_NAME CLI_ROLE_NAME SVID_SECRET_NAME SPIFFE_CA_SECRET_NAME \
           DEMO_LABEL_VALUE JOIN_TOKEN_TTL ENABLE_DB_SERVICE DB_CLIENT_CA_SECRET_NAME \
           TELEPORT_AGENT_RELEASE; do
  [[ -n "${!var:-}" ]] || die "$var is not set in .env (see .env.example)."
done

# ---------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------
log "Checking required tools"
for cmd in tctl tsh kubectl helm python3 curl jq; do
  require_cmd "$cmd"
  info "$cmd found"
done

log "Checking Teleport authentication"
tctl status >/dev/null 2>&1 || die "tctl isn't authenticated against a cluster. Run: tsh login --proxy=$TELEPORT_PROXY_ADDR"
info "tctl is authenticated"

# tctl calls without --auth-server (most of this script) silently use
# whichever tsh profile is currently active, regardless of TELEPORT_PROXY_ADDR
# -- so those succeed even against the wrong cluster. But the couple of
# calls that DO pass --auth-server="$TELEPORT_PROXY_ADDR" explicitly (e.g.
# the db_client CA export below) only find credentials if that address
# matches an actual saved tsh profile; if it doesn't, tctl finds nothing to
# use and falls through to assuming it's running directly on an Auth
# Service host, producing an unrelated-looking "Could not load Teleport
# host UUID file" error. Catch the mismatch here, before anything is
# created, rather than partway through a run.
ACTIVE_TSH_HOST="$(tsh status --format=json 2>/dev/null | jq -r '.active.profile_url // empty' | sed -E 's#^https?://##; s#:[0-9]+$##')"
CONFIGURED_HOST="${TELEPORT_PROXY_ADDR%%:*}"
if [[ -n "$ACTIVE_TSH_HOST" && "$ACTIVE_TSH_HOST" != "$CONFIGURED_HOST" ]]; then
  die "Your active tsh login ($ACTIVE_TSH_HOST) doesn't match TELEPORT_PROXY_ADDR ($TELEPORT_PROXY_ADDR) in .env -- update .env or run: tsh login --proxy=$TELEPORT_PROXY_ADDR"
fi

if [[ -z "${TBOT_IMAGE_TAG:-}" ]]; then
  log "TBOT_IMAGE_TAG not set -- detecting cluster version from /webapi/ping"
  TBOT_IMAGE_TAG="$(curl -fsS "https://$TELEPORT_PROXY_ADDR/webapi/ping" | jq -r '.server_version')"
  [[ -n "$TBOT_IMAGE_TAG" && "$TBOT_IMAGE_TAG" != "null" ]] || die "Could not detect server_version from https://$TELEPORT_PROXY_ADDR/webapi/ping -- set TBOT_IMAGE_TAG in .env instead."
  info "Using tbot image tag $TBOT_IMAGE_TAG (from cluster's server_version)"
fi

log "Ensuring namespace \"$NAMESPACE\" exists"
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun_info "kubectl create namespace $NAMESPACE"
  else
    kubectl create namespace "$NAMESPACE"
  fi
fi

# Common flags applied to every `helm upgrade --install` below (via
# helm_install(), see above).
HELM_FLAGS=()
if [[ "$DRY_RUN" == "true" ]]; then
  HELM_FLAGS+=(--dry-run=client)
else
  HELM_FLAGS+=(--wait --timeout 5m)
fi
[[ "$DEBUG" == "true" ]] && HELM_FLAGS+=(--debug)

# ---------------------------------------------------------------------
# Teleport resources that are always applied
# ---------------------------------------------------------------------
log "Applying Teleport resources (workload_identity, roles, bot)"
apply_teleport_resource teleport/workload_identity.yaml
info "workload_identity/$WORKLOAD_IDENTITY_NAME"
apply_teleport_resource teleport/role-tbot.yaml
info "role/$BOT_NAME"
apply_teleport_resource teleport/bot.yaml
info "bot/$BOT_NAME"
apply_teleport_resource teleport/role-human-cli.yaml
info "role/$CLI_ROLE_NAME -- assign it to yourself: tctl users update <you> --set-roles=<existing-roles>,$CLI_ROLE_NAME"

# ---------------------------------------------------------------------
# Optional: Teleport Database Access + auto-user-provisioning role and
# db_client CA. Both are independent of postgres-chart/tbot-chart timing
# now (the agent gets Postgres' server CA via a mounted Secret, not
# inline content baked in here), so this can happen up front with
# everything else.
# ---------------------------------------------------------------------
if [[ "$ENABLE_DB_SERVICE" == "true" ]]; then
  log "ENABLE_DB_SERVICE=true: setting up Database Access"
  apply_teleport_resource teleport/role-db-access.yaml
  info "role/${CLI_ROLE_NAME}-db-access -- assign it to yourself: tctl users update <you> --set-roles=<existing-roles>,${CLI_ROLE_NAME}-db-access"
  # Exports the cluster's db_client CA (public cert only) so postgres-chart
  # can add it to ssl_ca_file -- that's what lets Postgres trust the client
  # certs the Database Service presents on your behalf via `tsh db connect`.
  # NOTE: `--auth-server` only says where to connect; it does NOT supply
  # credentials (no `-i/--identity` is passed here), so this call runs on
  # your ambient `tsh` login, same as every other tctl call in this script.
  # If that session isn't present (fresh shell, sudo, CI, etc.), this falls
  # through to tctl's local-auth-server default and fails with a confusing
  # "Could not load Teleport host UUID file" error -- that message implies
  # tctl thinks it's running directly on an Auth Service host, but the real
  # issue is just a missing/expired `tsh login`, not this command specifically.
  DB_CLIENT_CA_FILE="$(mktemp)"
  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun_info "tctl auth export --type=db-client --auth-server=$TELEPORT_PROXY_ADDR"
  else
    tctl auth export --type=db-client --auth-server="$TELEPORT_PROXY_ADDR" > "$DB_CLIENT_CA_FILE"
  fi
  upsert_secret_from_file "$DB_CLIENT_CA_SECRET_NAME" "db-client.cas" "$DB_CLIENT_CA_FILE"
  rm -f "$DB_CLIENT_CA_FILE"
  info "Secret/$DB_CLIENT_CA_SECRET_NAME populated"
else
  log "ENABLE_DB_SERVICE=false: removing any previous Database Access setup"
  kubectl delete secret "$DB_CLIENT_CA_SECRET_NAME" -n "$NAMESPACE" --ignore-not-found >/dev/null
  remove_teleport_resource "role/${CLI_ROLE_NAME}-db-access"
  info "Removed (if they existed): secret/$DB_CLIENT_CA_SECRET_NAME, role/${CLI_ROLE_NAME}-db-access"
fi

# ---------------------------------------------------------------------
# tbot's join token (see teleport/token.yaml for why this isn't a
# checked-in resource file)
# ---------------------------------------------------------------------
log "Generating a join token for tbot ($BOT_NAME, ttl=$JOIN_TOKEN_TTL)"
JOIN_TOKEN="$(generate_join_token "$JOIN_TOKEN_TTL" "[Bot]" "$BOT_NAME")" \
  || die "Could not create a join token for tbot. See teleport/token.yaml for the resource shape and create one by hand, then pass it with --set-string teleport.joinToken=<token> when installing tbot-chart."
info "Token generated (not printed -- it's a bearer credential)"

# ---------------------------------------------------------------------
# Workload Identity trust bundle: self-issue one using YOUR OWN tsh
# session (see clients/cli/README.md step 2 -- same command, same
# reason). No bot or join token needed for this part.
# ---------------------------------------------------------------------
log "Fetching the Workload Identity trust bundle"
SVID_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$SVID_TMPDIR"' EXIT
if [[ "$DRY_RUN" == "true" ]]; then
  dryrun_info "tsh workload-identity issue-x509 --output $SVID_TMPDIR --name-selector $WORKLOAD_IDENTITY_NAME --credential-ttl 10m"
  : > "$SVID_TMPDIR/svid_bundle.pem"
elif ! tsh workload-identity issue-x509 \
    --output "$SVID_TMPDIR" \
    --name-selector "$WORKLOAD_IDENTITY_NAME" \
    --credential-ttl 10m >/dev/null; then
  die "Could not self-issue the Workload Identity. Make sure your Teleport user has the '$CLI_ROLE_NAME' role: tctl users update <you> --set-roles=<existing-roles>,$CLI_ROLE_NAME"
fi
upsert_secret_from_file "$SPIFFE_CA_SECRET_NAME" "bundle.pem" "$SVID_TMPDIR/svid_bundle.pem"
info "Secret/$SPIFFE_CA_SECRET_NAME populated from svid_bundle.pem"

# ---------------------------------------------------------------------
# Helm: Postgres
# ---------------------------------------------------------------------
log "Deploying postgres-chart"
helm_install "postgres-$SUFFIX" ./postgres-chart \
  --dependency-update \
  --set spiffeCABundle.secretName="$SPIFFE_CA_SECRET_NAME" \
  --set databaseAccess.enabled="$ENABLE_DB_SERVICE" \
  --set databaseAccess.caBundle.secretName="$DB_CLIENT_CA_SECRET_NAME" \
  || die "postgres-chart install failed"

# ---------------------------------------------------------------------
# Helm: Teleport App+DB Service agent (official teleport-kube-agent
# chart). Deployed here, after postgres-chart, so "postgres"'s
# Service DNS already exists when the agent starts probing it. This
# app registration is only consumed by the human/CLI path (`tsh vnet`,
# see clients/cli/README.md) -- tbot below connects Workload Identity
# clients straight to Postgres' Service, not through this app.
#
# If you'd rather point an agent you already run elsewhere at Postgres
# instead of having setup.sh deploy a new one, set
# DEPLOY_TELEPORT_AGENT=false in .env and merge
# teleport/app-service-teleport-config.yaml (+
# teleport/db-service-teleport-config.yaml if ENABLE_DB_SERVICE=true)
# into its config yourself.
# ---------------------------------------------------------------------
if [[ "${DEPLOY_TELEPORT_AGENT:-true}" == "true" ]]; then
  log "Generating a join token for the Teleport agent (roles=App,Db, ttl=$JOIN_TOKEN_TTL)"
  AGENT_JOIN_TOKEN="$(generate_join_token "$JOIN_TOKEN_TTL" "[App, Db]")" \
    || die "Could not create a join token for the Teleport agent."

  log "Deploying the Teleport App+DB Service agent ($TELEPORT_AGENT_RELEASE)"
  # Built directly here using the chart's own top-level `apps`/
  # `databases` values (confirmed against the teleport-kube-agent chart
  # reference) rather than by rendering
  # teleport/{app,db}-service-teleport-config.yaml: those two files use
  # the nested `app_service:`/`db_service:` shape a real `teleport.yaml`
  # wants, which is NOT what this chart's own validation checks -- it
  # errors with "no application source is enabled" if you hand it that
  # shape under `teleportConfig:` instead of populating `apps:` directly.
  # Those two files are kept as reference for the DEPLOY_TELEPORT_AGENT=false
  # manual-merge path, where a real teleport.yaml is exactly what's needed.
  AGENT_VALUES_FILE="$(mktemp)"
  {
    echo "roles: \"app,db\""
    echo "proxyAddr: \"$TELEPORT_PROXY_ADDR\""
    echo "authToken: \"$AGENT_JOIN_TOKEN\""
    echo "updater:"
    echo "  enabled: ${AGENT_AUTO_UPGRADE:-true}"
    echo "apps:"
    echo "  - name: \"$APP_NAME\""
    echo "    uri: \"tcp://postgres.${NAMESPACE}.svc.cluster.local:5432\""
    echo "    labels:"
    echo "      demo: \"$DEMO_LABEL_VALUE\""
    if [[ "$ENABLE_DB_SERVICE" == "true" ]]; then
      # ca_cert_file below expects Postgres' server CA mounted here
      # (from postgres-chart's generated Secret, already installed by
      # this point).
      echo "extraVolumes:"
      echo "  - name: postgres-server-ca"
      echo "    secret:"
      echo "      secretName: postgres-server-ca"
      echo "extraVolumeMounts:"
      echo "  - name: postgres-server-ca"
      echo "    mountPath: /etc/teleport-postgres-ca"
      echo "    readOnly: true"
      echo "databases:"
      echo "  - name: \"$APP_NAME\""
      echo "    protocol: \"postgres\""
      echo "    uri: \"postgres.${NAMESPACE}.svc.cluster.local:5432\""
      echo "    admin_user:"
      echo "      name: \"teleport-admin\""
      echo "    tls:"
      echo "      mode: verify-full"
      echo "      ca_cert_file: /etc/teleport-postgres-ca/ca.crt"
      echo "    static_labels:"
      echo "      demo: $DEMO_LABEL_VALUE"
    fi
  } > "$AGENT_VALUES_FILE"
  helm_install "$TELEPORT_AGENT_RELEASE" teleport-kube-agent \
    --repo https://charts.releases.teleport.dev \
    --version "$TBOT_IMAGE_TAG" \
    -f "$AGENT_VALUES_FILE" \
    || die "Teleport agent install failed. If the error above mentions a ClusterRole/ClusterRoleBinding already owned by another release, TELEPORT_AGENT_RELEASE=\"$TELEPORT_AGENT_RELEASE\" collides with someone else's release on this cluster (those objects are cluster-scoped, not per-namespace) -- pick a more unique name in .env and re-run."
  rm -f "$AGENT_VALUES_FILE"
  unset AGENT_JOIN_TOKEN
else
  log "DEPLOY_TELEPORT_AGENT=false: not deploying an agent"
  info "Merge teleport/app-service-teleport-config.yaml (and db-service-teleport-config.yaml if ENABLE_DB_SERVICE=true) into your own agent's config."
fi

# ---------------------------------------------------------------------
# Helm: tbot
# ---------------------------------------------------------------------
log "Deploying tbot-chart"
helm_install "$BOT_NAME" ./tbot-chart \
  --set fullnameOverride="$BOT_NAME" \
  --set teleport.proxyAddress="$TELEPORT_PROXY_ADDR" \
  --set-string teleport.joinToken="$JOIN_TOKEN" \
  --set teleport.workloadIdentityName="$WORKLOAD_IDENTITY_NAME" \
  --set svidOutput.secretName="$SVID_SECRET_NAME" \
  --set image.tag="$TBOT_IMAGE_TAG" \
  || die "tbot-chart install failed"

# ---------------------------------------------------------------------
# Python/Go client CronJobs (schedule: "*/2 * * * *" by default -- one
# transaction every two minutes; cron's minimum granularity is one
# minute). They connect
# straight to Postgres' own Service using the SVID tbot writes above as
# their client certificate -- no Teleport-mediated network hop, unlike
# the human/CLI path (see clients/*/chart/values.yaml's `postgres.host`
# default, which this doesn't need to override -- Postgres' Service
# name is fixed regardless of $SUFFIX, see postgres-chart/values.yaml's
# fullnameOverride).
#
# No registry needed by default: each run self-compiles from its own
# bundled source in a stock `ubuntu` image at container start (see
# clients/{python,go}/chart/values.yaml's `selfCompile`). Set
# CLIENT_IMAGE_REGISTRY to instead build+push a real image per
# ../clients/*/Dockerfile and use that (selfCompile.enabled=false).
# ---------------------------------------------------------------------
deploy_client() {
  local lang="$1" chart_dir="$2"
  log "Deploying the $lang client"
  local extra_args=()
  if [[ -n "${CLIENT_IMAGE_REGISTRY:-}" ]]; then
    local image="$CLIENT_IMAGE_REGISTRY/postgres-wi-client-$lang"
    if [[ "$DRY_RUN" == "true" ]]; then
      dryrun_info "docker build -t $image:$CLIENT_IMAGE_TAG clients/$lang"
      dryrun_info "docker push $image:$CLIENT_IMAGE_TAG"
    else
      docker build -t "$image:$CLIENT_IMAGE_TAG" "clients/$lang"
      docker push "$image:$CLIENT_IMAGE_TAG"
    fi
    extra_args=(--set selfCompile.enabled=false --set image.repository="$image" --set image.tag="$CLIENT_IMAGE_TAG")
  fi
  # "${extra_args[@]+"${extra_args[@]}"}", not "${extra_args[@]}": bash
  # 3.2 (macOS's default /bin/bash) throws "unbound variable" under
  # `set -u` when expanding a declared-but-empty array -- fixed in bash
  # 4.4+, but this repo shouldn't assume a modern bash. Confirmed live.
  #
  # fullnameOverride is set explicitly (its chart default,
  # "postgres-wi-client-$lang", is otherwise fixed regardless of release
  # name -- same reasoning as tbot-chart's fullnameOverride below) so the
  # actual CronJob/ConfigMap objects get the suffix too, not just the
  # Helm release metadata.
  # svidSecretName is passed explicitly too: its chart default
  # ("postgres-wi-svid") only happened to match SVID_SECRET_NAME's own
  # old default before that variable started carrying $SUFFIX -- without
  # this, the client would keep mounting a Secret name tbot-chart no
  # longer creates.
  helm_install "pg-client-$lang-$SUFFIX" "$chart_dir" \
    --set fullnameOverride="pg-client-$lang-$SUFFIX" \
    --set postgres.user="$POSTGRES_DB_USER" \
    --set svidSecretName="$SVID_SECRET_NAME" \
    "${extra_args[@]+"${extra_args[@]}"}" \
    || die "$lang client install failed"
}

if [[ -n "${CLIENT_IMAGE_REGISTRY:-}" ]]; then
  [[ "$DRY_RUN" == "true" ]] || require_cmd docker
fi
[[ "${DEPLOY_PYTHON_CLIENT:-true}" == "true" ]] && deploy_client python ./clients/python/chart
[[ "${DEPLOY_GO_CLIENT:-true}" == "true" ]] && deploy_client go ./clients/go/chart
if [[ "$DRY_RUN" != "true" ]]; then
  info "Client CronJobs deployed, but their first run can take a few minutes to show up:"
  info "up to 2 minutes waiting for the first scheduled tick, then another ~15-30s per run"
  info "for the self-compile (apt-get/pip/go build) before it even attempts to connect --"
  info "see item 5 below to check on them, and don't mistake that wait for a hang."
fi

# ---------------------------------------------------------------------
# Done -- how to confirm this actually works
# ---------------------------------------------------------------------
log "Setup complete. Confirm the deployment is healthy:"
cat <<EOF

  1. Postgres is up:
       kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=postgres-$SUFFIX
       kubectl exec -n $NAMESPACE postgres-0 -- pg_isready

  2. tbot joined and is issuing SVIDs:
       kubectl logs -n $NAMESPACE deploy/$BOT_NAME --tail=50
       kubectl get secret $SVID_SECRET_NAME -n $NAMESPACE   # should exist within ~renewal_interval of tbot starting

  3. Postgres' own Service is reachable in-cluster (the network path
     the Python/Go clients connect over directly, using the SVID as
     their client cert -- no Teleport-mediated hop for this path):
       kubectl run -n $NAMESPACE pg-reachability-check --rm -it --restart=Never --image=postgres:16-alpine \\
         -- pg_isready -h postgres -p 5432

  4. End-to-end transaction via the CLI (no cluster access needed once tunneled):
       see clients/cli/README.md

  5. End-to-end transaction via CronJobs (every two minutes, self-compiling -- each run takes ~30s):
       # First run can take a few minutes to show up: up to 2 minutes for the
       # first scheduled tick, then ~15-30s self-compiling (apt-get/pip/go
       # build) before it even attempts to connect -- not a hang.
       kubectl get cronjob -n $NAMESPACE
       kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/instance=pg-client-python-$SUFFIX
       kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=pg-client-python-$SUFFIX --tail=20
       kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=pg-client-go-$SUFFIX --tail=20
       # To trigger a run immediately instead of waiting for the schedule:
       kubectl create job -n $NAMESPACE --from=cronjob/pg-client-python-$SUFFIX manual-py-\$(date +%s)

  6. Teleport resources look right:
       tctl get workload_identity/$WORKLOAD_IDENTITY_NAME
       tctl get bot/$BOT_NAME
       kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$TELEPORT_AGENT_RELEASE --tail=50   # should show it joined and heartbeating the "postgres" app
EOF
if [[ "$ENABLE_DB_SERVICE" == "true" ]]; then
cat <<EOF
  7. Database Access + auto-provisioning (ENABLE_DB_SERVICE=true):
       tctl get db/$APP_NAME
       tsh db connect --db-name=demo --db-roles=reader,writer $APP_NAME
EOF
fi

# ---------------------------------------------------------------------
# The README/clients/cli/README.md walkthroughs use these as $VAR
# references (they carry $SUFFIX, so they're not the literal strings
# in teleport/*.yaml's comments) -- paste this block into another
# terminal to run them there without needing to `source .env` yourself.
# ---------------------------------------------------------------------
cat <<EOF

  Resolved names for this install -- paste into another shell to run
  the README/clients/cli/README.md walkthroughs there (or just
  \`cd $SCRIPT_DIR && set -a && source .env && set +a\`):

    export TELEPORT_PROXY_ADDR=$TELEPORT_PROXY_ADDR
    export NAMESPACE=$NAMESPACE
    export WORKLOAD_IDENTITY_NAME=$WORKLOAD_IDENTITY_NAME
    export APP_NAME=$APP_NAME
    export CLI_ROLE_NAME=$CLI_ROLE_NAME
    export BOT_NAME=$BOT_NAME
    export SPIFFE_CA_SECRET_NAME=$SPIFFE_CA_SECRET_NAME
    export SUFFIX=$SUFFIX
EOF
