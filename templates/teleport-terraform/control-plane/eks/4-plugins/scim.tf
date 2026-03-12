# 4-plugins/scim.tf
#
# SCIM plugin bootstrap — run once after `terraform apply` on this layer.
#
# The Teleport operator does not expose a TeleportPlugin CRD, so the plugin
# is registered via tctl. The resulting credentials are consumed by the
# Okta Terraform config at ~/github/okta/.
#
# ── Step 1: register the SCIM plugin ─────────────────────────────────────────
#
# Requires Teleport admin privileges. Run via the auth pod:
#
#   AUTH_POD=$(kubectl get pod -n teleport-cluster \
#     -l app.kubernetes.io/component=auth \
#     -o jsonpath='{.items[0].metadata.name}')
#   kubectl exec -n teleport-cluster "$AUTH_POD" -- \
#     tctl plugins install scim --connector=okta-integrator
#
# Output:
#   SCIM Base URL  →  https://<proxy>/v1/webapi/scim
#   Bearer Token   →  export TF_VAR_teleport_scim_token="<token>"
#
# ── Step 2: configure Okta (web UI, one-time) ─────────────────────────────────
#
#   Okta Admin → Applications → Teleport app → Provisioning tab
#   → Configure API Integration → Enable API Integration
#     SCIM connector base URL:  <base URL from step 1>
#     Unique identifier field:  userName
#     Supported actions:        Push New Users, Push Profile Updates, Push Groups
#     API Token:                <bearer token from step 1>
#   → Test API Credentials → Save
#
# ── Step 3: configure Push Groups (Okta UI — provider has no resource for this) ──
#
#   Okta Admin → EKS Demo app → Push Groups tab
#   → Push Groups → Find groups by name
#   Add each group and select Push Now: Everyone, engineers, devs
#
# ── Step 4: apply ~/github/okta/ ─────────────────────────────────────────────
#
#   cd ~/github/okta
#   export TF_VAR_teleport_scim_token="<bearer token from step 1>"
#   export TF_VAR_okta_api_token="<okta api token>"
#   terraform apply
#
# This injects the SCIM bearer token and pushes the Everyone/engineers/devs
# groups to Teleport, populating the Access Lists defined in 3-rbac/.
#
# ── Access Lists (managed in 3-rbac/) ────────────────────────────────────────
#
#   everyone   (type=scim)  →  base-user
#   devs       (type=scim)  →  dev-access, dev-auto-access, dev-requester
#   engineers  (type=scim)  →  platform-dev-access, dev-reviewer,
#                              prod-requester, prod-reviewer
