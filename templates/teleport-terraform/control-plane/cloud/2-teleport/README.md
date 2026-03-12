# Cloud Control Plane — Layer 2: Teleport

Configures the Teleport Cloud tenant: SAML connector (Okta) and auth preference. No AWS infrastructure is created — this layer uses the Teleport provider only.

Connects directly to the Teleport Cloud cluster via `var.proxy_address`.

See [../README.md](../README.md) for the full cloud control plane deployment guide and layer sequence.
