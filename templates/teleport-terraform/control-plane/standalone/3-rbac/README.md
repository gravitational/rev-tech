# Standalone Control Plane — Layer 3: RBAC

Configures Teleport roles, access lists, SAML connector (Okta), and auth preference via the Teleport Terraform provider. Defines the three-tier demo role hierarchy: `devs`, `senior-devs`, `engineers`.

Connects directly to the Teleport cluster via `var.proxy_address`. Run after layer 2 is healthy and `tsh login` succeeds.

See [../README.md](../README.md) for the full standalone control plane deployment guide and layer sequence.
