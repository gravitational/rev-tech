# EKS Control Plane — Layer 3: RBAC

Configures Teleport roles, access lists, SAML connector (Okta), and auth preference via the Teleport Kubernetes operator (TeleportRoleV7 CRDs). Defines the three-tier demo role hierarchy: `devs`, `senior-devs`, `engineers`.

Reads no prior layer state — connects directly to the Teleport cluster via `var.proxy_address`.

See [../README.md](../README.md) for the full EKS control plane deployment guide and layer sequence.
