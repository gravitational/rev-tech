# presets/conference.tfvars
#
# Conference booth backend. Self-contained: stands up its own data-plane
# resources AND its own demo RBAC (modules/demo-rbac) plus local demo
# personas. It does not depend on the cluster's existing roles.
# Companion runbook: docs/conference-event-runbook.md (build checklist,
# morning pre-flight, teardown order).
#
# Covers the three demo tracks' Show sections:
#   Track A (Attack Surface)  -> SSH, Database, Access Requests
#   Track B (Audit/Detection) -> SSH, Database, Access Graph*, MCP audit beat
#   Track C (ZSP + Graph)     -> SSH login, Access Requests, Access Graph*
#
# * Access Graph is a cluster-level feature, not stood up by this preset —
#   enable it on the event cluster's control plane.
#
# Deploy:
#   tsh login --proxy=<event-cluster> --auth=<connector>
#   eval $(tctl terraform env)
#   export TF_VAR_proxy_address=<event-cluster>
#   export TF_VAR_user=<you>@goteleport.com    # deployer email -> tags
#   cd profiles
#   terraform init
#   terraform apply -var-file=presets/conference.tfvars
#
# After apply, read the two outputs you need at the booth:
#   terraform output connection_guide   # exact tsh commands for what's deployed
#   terraform output demo_user_setup    # one-time persona activation + reviewer grant
#
# Destroy: FOLLOW THE TEARDOWN RUNBOOK in docs/conference-event-runbook.md
# (strip role holders and connector mappings first), then:
#   terraform destroy -var-file=presets/conference.tfvars

profile_label = "conference" # set per event (e.g. "kubecon-2027") -> resource tags

# --- Server Access ---
enable_ssh      = true # dev-ssh-0, dev-ssh-1  (Section 2)
enable_ssh_prod = true # prod-ssh-0, invisible until an access request is approved
#                      # also creates the JIT role trio + demo-requester/demo-reviewer (Section 6)

# --- Demo RBAC: canonical (unprefixed) role names for the published playbook ---
# Roles: dev-access, staging-access, prod-access, prod-access-mfa,
#        demo-requester, demo-reviewer. prod-access-mfa enforces per-session
#        webauthn MFA (hardware-key policy would require YubiKeys at the booth).
demo_rbac_role_prefix = ""
auto_approve_reason   = "authorized job" # staging-access requests with exactly this reason auto-approve
request_max_duration  = "168h"           # playbook: requests up to 7 days
extra_demo_user_names = ["alice"]        # station 2 persona — one demo user per workstation
#                                        # (shared personas collide: tctl lock --user=X kills BOTH stations)

# --- Database Access ---
enable_postgres = true # postgres-dev, cert auth, no passwords  (Section 4)

# --- Application Access ---
enable_demo_panel = true # demo-panel-dev, Flask panel showing the JWT identity claims
enable_grafana    = true # grafana-dev, JWT auto-login — a real app consuming the same
#                        # Teleport-Jwt-Assertion the demo panel visualizes

# --- Desktop Access ---
enable_windows = true # Windows Server + desktop service; browser RDP, per-identity
#                     # local users created on the fly (no shared Administrator password).
#                     # Web UI only — no tsh command. Allow ~10-15 min to boot + register.

# --- Machine / Non-Human Identity ---
enable_mcp = true # mcp-filesystem-dev + bot (Track B NHI/AI beat)
# Read-only MCP tool allowlist on dev-access. Teleport FILTERS denied tools out
# of tools/list (an AI client is never offered write_file), and direct calls to
# unlisted tools are denied and audited (mcp.session.request, success=false).
# Demo it with MCP Inspector, not an AI app — see the guide's Section 8.
mcp_tools      = ["read_*", "list_*", "search_files", "get_file_info", "directory_tree"]
enable_ansible = true # dev-ansible + bot, cert-based automation, no static keys (Track A story)

# --- Defaults left as-is ---
# create_demo_rbac = true  (self-contained roles + local personas)
# env / prod_env / team    = dev / prod / platform
# ssh_dev_count            = 2
# create_nat_gateway       = false  (public subnet, inbound blocked by SG; keep for booth)
