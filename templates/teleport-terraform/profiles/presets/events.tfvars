# presets/events.tfvars
#
# Conference / event booth backend. Self-contained: stands up its own
# data-plane resources AND its own demo RBAC (modules/demo-rbac) plus a local
# "bob" user, so it does not depend on any roles the target cluster already
# has. Deliberately event-NEUTRAL — no event name, date, or branding lives in
# this file, so the same preset serves every event.
#
# Covers three reusable demo tracks:
#   Attack Surface     -> SSH, Database, Access Requests
#   Audit / Detection  -> SSH, Database, Access Graph*, MCP audit beat
#   ZSP + Graph        -> SSH login, Access Requests, Access Graph*
#
# * Access Graph is a cluster-level feature, not stood up by this preset.
#   Confirm the target cluster has it enabled before promising it in a demo.
#
# Deploy:
#   tsh login --proxy=<cluster> --auth=okta
#   eval $(tctl terraform env)                 # provider creds; see below
#   export TF_VAR_proxy_address=<cluster>
#   export TF_VAR_user=you@example.com         # deployer email -> role prefix + tags
#   cd profiles
#   terraform init
#   terraform apply -var-file=presets/events.tfvars
#
# After apply, read the two outputs you need at the booth:
#   terraform output connection_guide   # exact tsh commands for what's deployed
#   terraform output demo_user_setup    # one-time bob activation + reviewer grant
#
# ---------------------------------------------------------------------------
# Carried forward from the last event (docs/conference-event-runbook.md). These
# cost real time once; don't re-learn them at a booth.
#
#   1. EVERYTHING in profiles/presets/ is tracked. The blanket `*.tfvars` ignore
#      is cancelled for the whole directory by `!profiles/presets/*.tfvars`, and
#      that negation exists because the blanket rule once hid a booth preset on a
#      single laptop for a month.
#
#      The consequence runs the other way too, and it is the one that bites: a
#      preset here is NOT private. It needs no `git add -f`, it shows up as
#      untracked in `git status`, and one `git add .` commits it. So a fork named
#      after an event is how event branding reaches a PUBLIC repo -- which is
#      exactly what happened to a `blackhat-2026.tfvars` that sat untracked in
#      this directory. Keep any fork event-neutral in name and content, or keep
#      it outside profiles/presets/ entirely.
#   2. Get terraform state OFF the laptop before the event. Use a remote
#      backend in the event's region, or at minimum copy the state file daily.
#      An event has previously run entirely on an unbacked local tfstate.
#   3. Land ALL SSO connector role-mappings at env-build time. Mappings ride the
#      connector in the gitops repo and need the owner's review, so a mid-event
#      mapping change means working around it with a local admin user.
#   4. Enroll persona MFA on the ACTUAL station hardware early, and keep the
#      cluster at `second_factor: on` (webauthn preferred, TOTP allowed). The
#      TOTP fallback is what makes a clean-slate VM rehearsal possible.
#   5. Official signed `tsh` only on demo machines. Device Trust and
#      hardware-key webauthn both reject community builds — never brew-install
#      teleport on a station.
#   6. Check every plan for REPLACEMENTS before applying. A new upstream AMI
#      once nearly replaced 8 healthy instances mid-prep. Instance modules now
#      carry `ignore_changes = [ami]`, but keep the habit; and never live-edit
#      an agent's teleport.yaml over its own tunnel — replace the node instead.
#
# Teardown ORDER matters (full runbook in docs/conference-event-runbook.md):
#   1. Strip terraform-managed roles from any NON-terraform users holding them,
#      or role deletion fails with "role is still in use by a user".
#   2. Remove the demo role names from the SSO connector mapping and verify
#      with `tctl get saml/<connector>` BEFORE deleting roles. Deleting a role
#      the connector still maps breaks every SSO login with "role not found".
#   3. `terraform destroy -var-file=presets/events.tfvars`
#   4. Only then does the control-plane owner delete the cluster and DNS.
#   Destroy the data plane the SAME DAY the event ends — a profile left up
#   "just in case" has previously sat live for days past its teardown date.
# ---------------------------------------------------------------------------

profile_label = "events"

# --- Server Access ---
enable_ssh      = true # dev-ssh-0, dev-ssh-1
enable_ssh_prod = true # prod-ssh-0, invisible until an access request is approved;
#                      # also creates the JIT role trio + demo-requester/demo-reviewer

# --- Demo RBAC: canonical (unprefixed) role names for the published playbook ---
# Roles: dev-access, staging-access, prod-access, prod-access-mfa,
#        demo-requester, demo-reviewer. prod-access-mfa enforces per-session
#        webauthn MFA, which a station's YubiKey satisfies.
# All five settings below are declared in profiles/variables.tf and passed to
# modules/demo-rbac in profiles/main.tf. Leaving any of them out falls back to
# the variable default: role names prefixed with the deployer's username, no
# auto-approve rule, a 1h request cap, bob only, and every MCP tool allowed.
demo_rbac_role_prefix = ""
auto_approve_reason   = "authorized job" # staging-access requests with exactly this reason auto-approve
request_max_duration  = "168h"           # playbook: requests up to 7 days
demo_user_name        = "bob"            # station 1 persona
extra_demo_user_names = ["alice"]        # one persona per workstation; add one name per extra station
#                                        # (shared personas collide: tctl lock --user=X kills every
#                                        # station using X, mid-demo)

# --- Database Access ---
enable_postgres = true # postgres-dev, cert auth, no passwords

# --- Application Access ---
enable_demo_panel = true # demo-panel-dev, Flask panel showing the JWT identity claims
enable_grafana    = true # grafana-dev, JWT auto-login — a real app consuming the same
#                        # Teleport-Jwt-Assertion the demo panel visualizes

# --- Desktop Access ---
enable_windows = true # Windows Server + desktop service; browser RDP, per-identity
#                     # local users created on the fly (no shared Administrator password).
#                     # Web UI only — no tsh command. Allow ~10-15 min to boot + register.

# --- Machine / Non-Human Identity ---
enable_mcp = true # mcp-filesystem-dev (stdio) + mcp-everything-dev (streamable-HTTP) + bot
# Read-only MCP tool allowlist on dev-access. Teleport FILTERS denied tools out
# of tools/list (an AI client is never offered write_file), and direct calls to
# unlisted tools are denied and audited (mcp.session.request, success=false).
# Demo it with MCP Inspector, not an AI client, which just says "I can't do
# that" with no visible denial. Inspector shows the per-identity toolset side
# by side.
mcp_tools      = ["read_*", "list_*", "search_files", "get_file_info", "directory_tree"]
enable_ansible = false # dev-ansible + bot, cert-based automation, no static keys

# --- Defaults left as-is ---
# create_demo_rbac = true  (self-contained roles + local bob user)
# env / prod_env / team    = dev / prod / platform
# ssh_dev_count            = 2
# create_nat_gateway       = false  (public subnet, inbound blocked by SG; keep for booth)
