# Integrations — Teleport with Third-Party Platforms

This directory contains demos that show how Teleport connects with external products and platforms,
enabling zero-trust identity to flow into systems that have their own authentication models.

## Demos

### [vault](vault/README.md)

Authenticate to HashiCorp Vault using **Teleport Workload Identity X.509 SVIDs** — no static tokens,
passwords, or secrets stored anywhere. Vault's cert auth method validates the SPIFFE certificate directly
against the Teleport SPIFFE CA, with no Teleport network proxy in the path.

**Run with:** [`vault/vault-auth-via-svid/vault-auth-via-svid.ipynb`](vault/vault-auth-via-svid/vault-auth-via-svid.ipynb)

---

Each demo has its own `README.md` with setup steps and a `.env.example` to configure before running.
Where a Jupyter notebook exists it is the recommended way to run the demo — it walks through every step
interactively with explanations inline.
