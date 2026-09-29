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
# Carried forward from the last event's retro (docs/events/*/retro.md). These
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
# Teardown ORDER matters (full runbook in the retro):
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

# --- Demo RBAC ---
# Roles created by modules/demo-rbac: dev-access, staging-access, prod-access,
# prod-access-mfa, demo-requester, demo-reviewer — each PREFIXED with the
# deployer's username (e.g. you-dev-access), because profiles/main.tf passes
# name_prefix = local.user_prefix unconditionally.
demo_user_name = "bob" # the single persona the profiles stack supports today
#
# ⚠ NOT WIRED — the five settings below were carried in the previous event
# preset and silently did NOTHING. terraform treats values for undeclared
# variables as a WARNING, not an error, so the preset appeared to configure
# behaviour the stack cannot deliver, and the published playbook promised it.
# They are commented out so this file stays honest. To make any of them real,
# declare it in profiles/variables.tf and pass it through in profiles/main.tf:
#
#   demo_rbac_role_prefix = ""            # declared NOWHERE. main.tf hardcodes
#                                         # name_prefix; canonical unprefixed
#                                         # role names are impossible until that
#                                         # becomes a variable.
#   auto_approve_reason   = "authorized job"  # declared NOWHERE.
#   request_max_duration  = "168h"        # EXISTS in modules/demo-rbac, but
#                                         # main.tf's demo_rbac block never
#                                         # passes it — one line to wire.
#   extra_demo_user_names = ["alice"]     # declared NOWHERE. Only the singular
#                                         # demo_user_name above is supported, so
#                                         # a second station needs a second apply
#                                         # or a manual user.
#   mcp_tools = ["read_*", "list_*", "search_files", "get_file_info", "directory_tree"]
#                                         # EXISTS in modules/machineid-bot, not
#                                         # wired from the root. Without it the
#                                         # MCP demo has NO tool allowlist, so
#                                         # the RBAC-denial beat does not work.
#
# Booth practice that does NOT depend on the above: use ONE persona per
# workstation. Shared personas collide — `tctl lock --user=X` kills every
# station using X, mid-demo.

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
enable_mcp = true # mcp-filesystem-dev + bot
#
# ⚠ The tool allowlist (mcp_tools) is NOT wired from this preset — see the Demo
# RBAC block above. Until it is, the MCP server is registered with NO Teleport
# tool filtering, so the "write_file is denied and the denial lands in the audit
# log" beat will NOT work. Either wire mcp_tools through, or set the allowlist
# directly on the role with tctl before demoing that beat.
#
# When it does work, demo it with MCP Inspector, NOT an AI client: Teleport
# filters denied tools out of tools/list, so an AI app just says "I can't do
# that" with no visible denial. Inspector shows the per-identity toolset side
# by side.
enable_ansible = false # dev-ansible + bot, cert-based automation, no static keys

# --- Defaults left as-is ---
# create_demo_rbac = true  (self-contained roles + local bob user)
# env / prod_env / team    = dev / prod / platform
# ssh_dev_count            = 2
# create_nat_gateway       = false  (public subnet, inbound blocked by SG; keep for booth)
