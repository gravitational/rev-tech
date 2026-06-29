# Vault — Teleport Workload Identity Integration

Authenticate to HashiCorp Vault using **X.509 SVIDs issued by Teleport Workload Identity**.
No static tokens, passwords, or pre-shared secrets — Vault validates the SPIFFE certificate
directly against the Teleport SPIFFE CA.

## How It Works

```
Workload
  │  tsh workload-identity issue-x509 --name-selector vault-test
  ↓
Teleport
  │  Issues X.509 SVID signed by Teleport SPIFFE CA
  │  URI SAN: spiffe://<cluster>/vault-test
  ↓
Vault cert auth
  │  Verifies cert against registered Teleport SPIFFE CA
  │  Checks URI SAN matches allowed_uri_sans glob
  │  Issues Vault token with attached policy
  ↓
Secret read / write (no Teleport proxy in path)
```

### App Access Proxy vs. Workload Identity

| | App Access Proxy | Workload Identity (this demo) |
|---|---|---|
| **Network path** | Teleport proxies to Vault | Direct connection |
| **Auth method** | Vault native (token, userpass…) | Vault cert auth via SPIFFE mTLS |
| **Audit log** | Teleport logs HTTP requests | Vault audit log + Teleport logs SVID issuance |
| **Best for** | Human SSO access to Vault UI/CLI | Machine-to-machine workload auth |

## Demos

### [vault-auth-via-svid](vault-auth-via-svid/vault-auth-via-svid.ipynb)

An end-to-end interactive walkthrough covering every step from Teleport RBAC setup through
reading a Vault secret in Python. Includes a Docker Compose Vault setup in the appendix for
self-contained local testing.

**Run with:** [`vault-auth-via-svid/vault-auth-via-svid.ipynb`](vault-auth-via-svid/vault-auth-via-svid.ipynb)

The notebook covers:

1. Teleport RBAC — `WorkloadIdentity` resource and issuer role
2. Exporting the Teleport SPIFFE CA (`tctl auth export --type=tls-spiffe`)
3. Vault cert auth configuration — CA registration, policy, test secret
4. Issuing an X.509 SVID with `tsh workload-identity issue-x509`
5. Authenticating to Vault with the `hvac` Python client
6. Reading secrets post-authentication
7. *(Optional)* Automated SVID renewal with `tbot`
8. **Appendix** — Docker Compose Vault setup with TLS for local development

## Prerequisites

- `tsh` and `tctl` (Teleport 18+)
- Active `tsh login` session with admin or equivalent access
- `vault` CLI
- `openssl`
- Python 3.11+
- Docker + Docker Compose *(only if using the appendix Vault setup)*

## Setup

```bash
cd vault-auth-via-svid
cp .env.example .env
# Edit .env — set TELEPORT_CLUSTER, TELEPORT_USER, VAULT_ADDR, VAULT_TOKEN
pip install -r requirements.txt
```

Open [`vault-auth-via-svid.ipynb`](vault-auth-via-svid/vault-auth-via-svid.ipynb) in Jupyter
and run cells in order. See the appendix cells at the bottom if you need to spin up a local Vault first.

## Files

| Path | Purpose |
|:-----|:--------|
| `vault-auth-via-svid/vault-auth-via-svid.ipynb` | Interactive walkthrough — the main demo |
| `vault-auth-via-svid/.env.example` | Environment variable template |
| `vault-auth-via-svid/requirements.txt` | Python dependencies (`hvac`, `python-dotenv`) |
