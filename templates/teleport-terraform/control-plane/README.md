# Control Plane Templates

Control-plane blueprints for provisioning Teleport clusters and RBAC. Each use case follows the same 3‑layer pattern so you can update Teleport and RBAC without re‑provisioning the base infrastructure.

## Layout Pattern

```
control-plane/<use-case>/
├── 1-cluster/     # infrastructure layer (stable)
├── 2-teleport/    # Teleport deployment + supporting AWS/K8s resources
├── 3-rbac/        # SSO/login rules, roles, and demo apps
└── update-teleport.sh
```

## Use Cases

- **eks** – EKS-based Teleport control plane split into infra, Teleport, and RBAC layers.
- **proxy-peer** – Self-hosted Teleport cluster with proxy peering, split into infra, Teleport, and RBAC layers.
- **cloud** – Teleport Cloud tenant configuration using the Teleport provider (no infra layer).

## Usage

Use `export TF_VAR_*` for configuration, mirroring the data‑plane templates. See each use‑case README for the full list of variables.

## SCIM Access Lists

Access List membership is managed via SCIM. Access List `spec.title` must match the Okta group `displayName` exactly (case‑sensitive).

## SCIM Checklist

- Enable SCIM in Teleport and associate it with your SAML connector.
- In Okta, configure SCIM provisioning with the Teleport SCIM base URL and client credentials.
- Ensure Okta group `displayName` values match Access List titles exactly:
  - `Everyone`
  - `devs`
  - `engineers`
- Run the `3-rbac` layer to create roles and SCIM Access Lists.

## SCIM/Okta Wiring (Minimal)

- Teleport: Integrations → SCIM → create integration, select your SAML connector, copy Base URL + Client ID/Secret.
- Okta: Provisioning → SCIM → paste Base URL + Client ID/Secret, enable Group Push/Assignments.
- Access Lists: `spec.title` **must** equal Okta group `displayName` (case‑sensitive).
