# Control Plane Templates

Cluster blueprints. Most SEs use a **Teleport Cloud** tenant — `cloud/` configures it. `standalone/` is the fastest path to a self-hosted cluster when the demo calls for one.

The EKS control plane (Slack plugin, SCIM, Access Graph — runs `presales.teleportdemo.com`) and the proxy-peer variant now live in [tenaciousdlg/teleport-terraform](https://github.com/tenaciousdlg/teleport-terraform).

## Layout Pattern

```
control-plane/<use-case>/
├── 1-cluster/     # infrastructure layer (stable; cloud has none — your tenant is the cluster)
├── 2-teleport/    # Teleport deployment / tenant configuration (SSO connector, auth prefs)
└── 3-rbac/        # roles (via modules/teleport-rbac), access lists, autoupdate schedule
```

**Layers are coupled through local state.** Each layer reads the previous layer's outputs with `data "terraform_remote_state"` pointing at `../<n-1>-*/terraform.tfstate` (local backend). That means:

- Run layers **in order, from their own directories**, with the default local backend.
- If you move state to a remote backend or run from another path, layer 2+ will fail to find layer 1's outputs — update the `terraform_remote_state` blocks to match.
- Destroy in **reverse order** (3 → 2 → 1).

## Use Cases

- **cloud** — Teleport Cloud tenant configuration (Teleport provider only, no AWS infra). `2-teleport` requires an Okta SAML app (`okta_metadata_url`); `3-rbac` creates the canonical role set and Terraform-managed access lists. If you only need demo RBAC for a profile deployment, you can skip this entirely — profiles create their own user-prefixed roles by default (`create_demo_rbac`).
- **standalone** — single-node EC2 self-hosted cluster. Requires a Route 53 hosted zone and, for Enterprise features, a `license.pem` placed at `control-plane/license.pem` (gitignored).

## Usage

Use `export TF_VAR_*` for configuration. See each use-case README for the full variable list.

Agent update schedules are managed cluster-side by the `teleport_autoupdate_config` resource in each `3-rbac` layer — agents enroll in [Managed Updates](https://goteleport.com/docs/upgrading/agent-managed-updates/) automatically at install.
