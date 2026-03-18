# Proxy-Peer Control Plane — Layer 3: RBAC

Configures Teleport roles, access lists, SAML connector (Okta), and auth preference via the Teleport Terraform provider. Mirrors the EKS 3-rbac layer for the proxy-peer deployment model.

Connects directly to the Teleport cluster via `var.proxy_address`. Run after layer 2 is healthy and `tsh login` succeeds.

See [../README.md](../README.md) for the full proxy-peer control plane deployment guide and layer sequence.
