# Vault — Teleport Workload Identity Integration

Authenticate to HashiCorp Vault using **X.509 SVIDs issued by Teleport Workload Identity**.
No static tokens, passwords, or pre-shared secrets — Vault validates the SPIFFE certificate
directly against the Teleport SPIFFE CA and issues its own token from there.

## Overview

Workloads and operators normally get into Vault one of two ways: a static token or userpass
credential sitting in a config file somewhere, or a Teleport Application Access proxy sitting in
front of Vault as a network gateway. Both work, but both mean Vault is trusting *something else*
to have already done the authenticating.

This integration takes a different approach: Vault becomes a **relying party** that trusts
Teleport-issued certificates directly. A workload asks Teleport's SPIFFE CA for a short-lived
X.509 SVID, presents it to Vault over mutual TLS, and Vault's `cert` auth method verifies the
certificate itself — no proxy, no shared secret, no long-lived credential anywhere on disk. The
identity is the certificate, and the certificate expires in an hour.

The [demo notebook](vault-auth-via-svid/vault-auth-via-svid.ipynb) in this directory walks through
every step of that flow hands-on, from configuring Teleport RBAC through reading a live secret
back out of Vault with the issued token. The sections below explain *why* each piece exists; follow
along in the notebook to see each one *work*.

## Application Access Proxy vs. Workload Identity

Registering Vault as a Teleport Application and routing `tsh apps login` traffic through the
Application Access proxy is still the right call when a workload or user doesn't have a direct
network path to Vault — Teleport gives you that path, plus an audit log and access controls over
who can reach Vault at all. That's exactly what you want for humans logging into the Vault UI or
CLI via SSO, or for reaching a Vault instance that's otherwise unreachable from where the caller
sits.

What the proxy *doesn't* do is authenticate you to Vault. It solves network access, not Vault
identity — once the connection lands, Vault still authenticates it with its own native auth method
(token, userpass, and so on), so you need a separate credential either way. This pattern is for the
case where a workload already has direct network access to Vault: it skips the proxy layer
entirely and lets Vault validate the Teleport CA and the SPIFFE ID directly at the TLS layer, so
network access and authentication happen in one step instead of two. Vault's own policies still
govern what the authenticated identity can touch either way.

| | App Access Proxy | Workload Identity (this demo) |
|---|---|---|
| **Network path** | Teleport proxies to Vault | Direct connection |
| **Auth method** | Vault native (token, userpass…) | Vault cert auth via SPIFFE mTLS |
| **Audit log** | Teleport logs HTTP requests | Vault audit log + Teleport logs SVID issuance |
| **SVID renewal** | Not applicable | Required — `tsh` for one-off issuance, `tbot` for automated workloads |
| **Vault config changes** | Register Vault as a Teleport app only | Export the SPIFFE CA, configure a cert auth role and policy |
| **Best for** | No direct network path to Vault; human SSO access to Vault UI/CLI | Machine-to-machine workload auth with direct network access to Vault |

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

The trust chain behind that diagram has four pieces, each covered in its own step of the notebook:

- **Teleport's SPIFFE CA** — a certificate authority Teleport maintains separately from its host
  and user CAs, dedicated to signing workload identities.
- **A `WorkloadIdentity` resource** — defines the SPIFFE ID path a given workload is allowed to
  claim, and the rules that gate who can claim it.
- **An issued X.509 SVID** — `tsh workload-identity issue-x509` (or `tbot`, for always-on
  workloads) asks Teleport to mint a short-lived certificate from that CA on the workload's behalf.
- **Vault's `cert` auth method** — configured to trust the Teleport SPIFFE CA and to accept only
  certificates whose SPIFFE ID matches a defined pattern, mapping the matched identity to a policy.

## Demos

### [vault-auth-via-svid](vault-auth-via-svid/vault-auth-via-svid.ipynb)

An end-to-end interactive walkthrough covering every step from Teleport RBAC setup through
reading a Vault secret in Python. Includes a Docker Compose Vault setup in the appendix for
self-contained local testing, so you can run the whole thing without needing a pre-existing Vault
cluster.

**Run with:** [`vault-auth-via-svid/vault-auth-via-svid.ipynb`](vault-auth-via-svid/vault-auth-via-svid.ipynb)

The notebook covers, in order:

1. Teleport RBAC — `WorkloadIdentity` resource and issuer role
2. Exporting the Teleport SPIFFE CA (`tctl auth export --type=tls-spiffe`)
3. Vault cert auth configuration — CA registration, policy, test secret
4. Issuing an X.509 SVID with `tsh workload-identity issue-x509`
5. Authenticating to Vault with the `vault` CLI
6. Reading a secret with the token issued to the SVID identity
7. *(Optional)* Automated SVID renewal with `tbot`, for workloads that need to run continuously
   rather than being issued a one-off identity by hand
8. **Appendix** — Docker Compose Vault setup with TLS for local development

Each markdown cell explains the *why* behind the step that follows it — read those alongside the
code as you run the notebook rather than skipping straight to execution; several steps (the
`common_name` field in the `WorkloadIdentity`, the `--type=tls-spiffe` export flag) fail in
non-obvious ways if skipped.

## Prerequisites

- `tsh` and `tctl` (Teleport 18+)
- Active `tsh login` session with admin or equivalent access
- `vault` CLI
- `openssl`
- Python 3.11+
- Docker + Docker Compose *(only if using the appendix Vault setup)*

This integration was validated with Teleport 18.8.3, HashiCorp Vault 2.0.3 (OSS), and `tsh` 18.8.3
on macOS (arm64). The `cert` auth method and SPIFFE CA export are available in every edition of
both products, so none of this is Enterprise- or Cloud-only.

## Setup

```bash
cd vault-auth-via-svid
cp .env.example .env
# Edit .env — set TELEPORT_CLUSTER, TELEPORT_USER, VAULT_ADDR, VAULT_TOKEN
pip install -r requirements.txt
```

Open [`vault-auth-via-svid.ipynb`](vault-auth-via-svid/vault-auth-via-svid.ipynb) in Jupyter
and run cells in order. See the appendix cells at the bottom if you need to spin up a local Vault first.

## Troubleshooting

The notebook raises on most failures with the underlying error, but a few of them are easy to
misread. If you hit one of these while following along:

| Symptom | Cause |
|:--------|:------|
| `missing name in alias` | The SVID has an empty CN. Add `subject_template.common_name` to the `WorkloadIdentity` resource. |
| `failed to match all constraints` | The CA registered in Vault doesn't match the SVID's issuer. Export with `--type=tls-spiffe`, not `tls-host`. |
| `access to workload_identity denied` | The role is missing `workload_identity_labels` or the `workload_identity_token` `use` rule — re-login after role changes. |
| Vault login fails with a TLS error | Vault's listener must not have `tls_disable_client_certs` set — cert auth requires mTLS. |
| SVID login succeeds then stops working an hour later | SVIDs default to a 1-hour TTL. Re-issue with `tsh workload-identity issue-x509`, or use `tbot` for automatic renewal. |

## Beyond the Demo: Per-Identity Policy Templating

The notebook attaches one fixed policy (`app-secrets`) to every SVID that matches the
`allowed_uri_sans` glob — good enough for a single workload, but not for isolating many workloads
behind one cert role. Vault's ACL policy templating can reference the CN from the authenticated
certificate to scope access per-identity, e.g.:

```hcl
path "secret/data/workloads/{{identity.entity.aliases.<mount_accessor>.metadata.common_name}}/*" {
  capabilities = ["read", "list"]
}
```

To use this, set `enable_identity_alias_metadata = true` on the cert role and template the CN in
the `WorkloadIdentity`'s `subject_template` to encode whatever distinguishes the workload (name,
environment, tier). Note that the SPIFFE ID itself isn't exposed as templateable metadata — only
the CN, serial number, and any OID extensions registered via `allowed_metadata_extensions` are.
That's the reason the notebook is careful to set `common_name` in the first place: it's the hook
everything else — Vault's alias name *and* any future per-workload policy — hangs off of.

## Files

| Path | Purpose |
|:-----|:--------|
| `vault-auth-via-svid/vault-auth-via-svid.ipynb` | Interactive walkthrough — the main demo |
| `vault-auth-via-svid/.env.example` | Environment variable template |
| `vault-auth-via-svid/requirements.txt` | Python dependencies (`python-dotenv`) — the demo shells out to the `vault` CLI directly rather than using the `hvac` client |
