# Cloud Control Plane — Layer 3: RBAC

Configures Teleport roles, access lists, and access monitoring rules via the Teleport provider. Defines the three-tier demo role hierarchy: `devs`, `senior-devs`, `engineers`. No AWS infrastructure is created.

Connects directly to the Teleport Cloud cluster via `var.proxy_address`. Run after layer 2 is complete.

See [../README.md](../README.md) for the full cloud control plane deployment guide and layer sequence.
