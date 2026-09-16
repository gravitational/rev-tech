# How certificates authenticate Postgres in this demo

Every connection to Postgres in this demo is mutual TLS: **two
independent certificate checks, both happening inside the same TLS
handshake**. This file walks through where each certificate/CA comes
from, which files generate them, and how Postgres turns "a valid
client certificate" into "you're logged in as `app_user`" with no
password anywhere.

If you just want the short version, see the "How the pieces fit
together" section of [README.md](README.md) -- this file is the
detailed walkthrough behind that diagram.

## The two trust relationships

```
                 ┌───────────────────────────────────────────────┐
                 │                     client                     │
                 │  (tbot / a human's tsh session / Database       │
                 │   Service, depending on the path)               │
                 └───────────────┬─────────────────────┬──────────┘
                                 │                       │
             1. client verifies │                       │ 2. server verifies
                Postgres' server │                       │    client's certificate
                certificate      │                       │    (mTLS "cert" auth)
                                 ▼                       ▼
                 ┌───────────────────────────────────────────────┐
                 │                    Postgres                     │
                 │  server cert:  self-signed by postgres-chart    │
                 │  ssl_ca_file:  Workload Identity bundle          │
                 │                (+ db_client CA if enabled)      │
                 └───────────────────────────────────────────────┘
```

1. **Client → Postgres**: the client checks that the certificate
   Postgres presents during the handshake is one it trusts, so it
   knows it's really talking to this Postgres instance.
2. **Postgres → client**: Postgres checks that the certificate the
   client presents chains up to a CA it trusts, *and* uses the
   certificate's Common Name (CN) as the Postgres role to log in as
   (`cert` authentication -- no password involved at all).

These two checks use **completely separate CAs** that have nothing to
do with each other. Mixing them up is the most common source of
confusion when reading this demo, so the rest of this file covers each
one on its own.

## 1. Postgres' server identity (client → Postgres)

Generated once, by this chart, and has nothing to do with Teleport.

- **Where**: [`postgres-chart/templates/tls-secrets.yaml`](postgres-chart/templates/tls-secrets.yaml).
- **What it does**: on first install, generates a self-signed CA
  (`genCA`) and a server certificate/key signed by it (`genSignedCert`),
  with SANs matching Postgres' own Kubernetes Service name -- always
  literally `postgres` regardless of the Helm *release* name, because
  [`postgres-chart/values.yaml`](postgres-chart/values.yaml) pins
  `fullnameOverride: "postgres"` for both this chart and the
  `bitnami/postgresql` subchart it wraps.
- **Where it's stored**: a Secret named `postgres-certs`
  (`postgresql.tls.certificatesSecret`), containing `tls.crt`/`tls.key`
  (the server's own cert/key) and `ca.crt` -- which, despite the name,
  is **not just this CA**. See the next section.
- **Reused across upgrades**: on every `helm upgrade`, the template
  looks up the existing Secret (`lookup "v1" "Secret" ...`) and reuses
  the CA/cert verbatim instead of regenerating them -- otherwise every
  `helm upgrade` would silently rotate Postgres' server identity out
  from under already-running clients.
- **Handed to clients as**: a second Secret, `postgres-server-ca`
  (just the public `ca.crt`, no key), which the Python/Go client charts
  mount and pass as `sslrootcert`, and which a human can fetch by hand
  (see `clients/cli/README.md` step 4).
- **`sslmode` differs by client, and that difference is itself part of
  the point being demonstrated:**
  - The Python/Go clients connect straight to Postgres' `postgres`
    Service (see [README.md](README.md)'s "How the pieces fit
    together" for why) -- that hostname *is* one of the server cert's
    SANs, so they use `sslmode=verify-full`
    and get full hostname pinning, same as any normal direct Postgres
    client would.
  - The CLI path goes through `tsh vnet` (Teleport TCP Application
    Access) -- the hostname it dials there is the app's Teleport-issued
    DNS name, which never matches the server cert's SANs. It uses
    `sslmode=require`/`verify-ca` instead: the chain of trust is still
    validated, just not the hostname, which is an acceptable trade-off
    here since Teleport's own access control already gates who can
    open that VNet session in the first place.

## 2. The client certificate Postgres trusts (Postgres → client)

This is the actual point of the demo: **the "password" is a SPIFFE
X.509-SVID issued by Teleport Workload Identity.**

### Where the client's certificate comes from

- **[`teleport/workload_identity.yaml`](teleport/workload_identity.yaml)**
  defines the SPIFFE identity (`kind: workload_identity`). The field
  that matters most for authentication is
  `spec.spiffe.x509.subject_template.common_name: ${POSTGRES_DB_USER}`
  (`app_user` by default) -- **whatever CN this resource stamps onto
  the issued certificate is the Postgres role the connection logs in
  as.** Change `POSTGRES_DB_USER` in `.env` and this value follows
  automatically, but it then has to also match a real Postgres role
  (see `03-teleport-db-service.sql`/`01-app-user-and-schema.sql` in
  `postgres-chart/values.yaml`).
- **Who can request that identity is pure RBAC**, not anything on the
  `workload_identity` resource itself: a caller needs a Teleport role
  whose `workload_identity_labels` match this resource's
  `demo: ${DEMO_LABEL_VALUE}` label. See
  [`teleport/role-tbot.yaml`](teleport/role-tbot.yaml) (for the
  always-on Python/Go clients, via `tbot`) and
  [`teleport/role-human-cli.yaml`](teleport/role-human-cli.yaml) (for a
  human running `tsh workload-identity issue-x509` directly).
- **Two ways the certificate actually gets issued:**
  - `tbot` (deployed by `tbot-chart`) requests it continuously and
    writes it to a Kubernetes Secret (`svidOutput.secretName`, e.g.
    `postgres-wi-svid-<suffix>`) as three files: `svid.pem` (cert),
    `svid_key.pem` (private key), `svid_bundle.pem` (trust bundle) --
    confirmed against a live Secret; this is *not* the same key naming
    the `directory` destination type uses. It reissues on
    `svidOutput.renewalInterval` (20m by default,
    `credentialTTL: 1h`), so the Python/Go clients (`connect()` in
    [`clients/python/chart/app/transact.py`](clients/python/chart/app/transact.py)
    and [`clients/go/chart/app/main.go`](clients/go/chart/app/main.go))
    re-read those files on every connection attempt rather than caching
    them, so a long-running process never presents an expired cert.
  - A human runs `tsh workload-identity issue-x509` directly against
    their own `tsh` session -- no `tbot`, no join token, just their own
    identity plus the `role-human-cli` role. See
    `clients/cli/README.md` step 2.

### How Postgres decides to trust it

- **`ssl_ca_file`** (Postgres' own setting, populated via the
  `postgres-certs` Secret's `ca.crt` field) is a **concatenation of up
  to three CAs**, built in `tls-secrets.yaml`:
  1. postgres-chart's own self-signed CA (see section 1) -- needed so
     `bitnami/postgresql`'s built-in health probes, which authenticate
     over loopback using the server's *own* `tls.crt`/`tls.key` as
     their client cert, don't fail their own TLS handshake.
  2. The **Teleport Workload Identity trust bundle** -- fetched by
     `setup.sh` using *your own* `tsh` session
     (`tsh workload-identity issue-x509 ... `, then the resulting
     `svid_bundle.pem` is loaded into the `teleport-spiffe-ca` Secret)
     and referenced via `spiffeCABundle.secretName` in
     `postgres-chart/values.yaml`. This is the CA that actually signs
     the SVIDs from the previous section.
  3. **Teleport's `db_client` CA** (`tctl auth export --type=db-client`),
     only when `ENABLE_DB_SERVICE=true` -- see the next section.
- **`pg_hba.conf`** (`postgresql.primary.pgHbaConfiguration` in
  `postgres-chart/values.yaml`) is what actually turns "presented a
  cert Postgres trusts" into "logged in as a specific role":
  ```
  hostssl  all  postgres  127.0.0.1/32  trust   # loopback probes only
  hostssl  all  postgres  ::1/128       trust
  hostssl  all  all       0.0.0.0/0     cert    # everyone else: cert auth
  hostssl  all  all       ::/0          cert
  host     all  all       0.0.0.0/0     reject  # no TLS at all: rejected
  host     all  all       ::/0          reject
  ```
  `cert` auth requires both a chain of trust to `ssl_ca_file` **and**
  the certificate's CN to match the Postgres username the client asked
  to connect as -- this is the step that makes `common_name: app_user`
  in `workload_identity.yaml` load-bearing rather than cosmetic.

## 3. The second path: plain Teleport Database Access (optional)

`ENABLE_DB_SERVICE=true` in `.env` (the default) turns on a second,
independent way to reach Postgres, for comparison -- no SVID files, no
shared `app_user`, Teleport auto-provisions a login per Teleport user.
It reuses the exact same `ssl_ca_file`/`cert`-auth machinery above, just
with a different certificate source:

- Teleport's **Database Service** (the `db_service` role on the
  `teleport-kube-agent` deployed by `setup.sh`) connects to Postgres
  presenting its own client certificate, signed by Teleport's
  `db_client` CA -- exported once via `tctl auth export --type=db-client`
  and stored in the `DB_CLIENT_CA_SECRET_NAME` Secret, which is why that
  CA has to be added into `ssl_ca_file` alongside the Workload Identity
  bundle (see previous section).
- That connection's CN is `teleport-admin` -- a bootstrap role created
  by `03-teleport-db-service.sql` in `postgres-chart/values.yaml`,
  granted `CREATEROLE` so it can provision a real Postgres login (named
  after your Teleport username) on demand, and `GRANT ... WITH ADMIN
  OPTION` on the `reader`/`writer` role groups your `tsh db connect
  --db-roles=...` flag selects from.
- You, the end user, never touch a certificate here at all -- Teleport
  handles the entire mTLS handshake to Postgres on your behalf, keyed
  off your own Teleport identity. See
  [`teleport/role-db-access.yaml`](teleport/role-db-access.yaml) for the
  RBAC side of who's allowed to use this path.

## Where each file fits

| Concern | File |
|---|---|
| Postgres' own server CA/cert, `postgres-certs`/`postgres-server-ca` Secrets | [`postgres-chart/templates/tls-secrets.yaml`](postgres-chart/templates/tls-secrets.yaml) |
| `pg_hba.conf`, `ssl_*` settings, `app_user`/`demo` bootstrap, `teleport-admin` bootstrap | [`postgres-chart/values.yaml`](postgres-chart/values.yaml) |
| The SPIFFE identity issued to clients (CN, TTL) | [`teleport/workload_identity.yaml`](teleport/workload_identity.yaml) |
| Who may request that identity (bot vs. human) | [`teleport/role-tbot.yaml`](teleport/role-tbot.yaml), [`teleport/role-human-cli.yaml`](teleport/role-human-cli.yaml) |
| Who may use the Database Access path instead | [`teleport/role-db-access.yaml`](teleport/role-db-access.yaml) |
| `tbot`'s SVID output (renewal interval, Secret name/keys) | [`tbot-chart/values.yaml`](tbot-chart/values.yaml) (`svidOutput`) |
| How a long-lived client reads/re-reads the SVID files per connection | [`clients/python/chart/app/transact.py`](clients/python/chart/app/transact.py), [`clients/go/chart/app/main.go`](clients/go/chart/app/main.go) |
| Doing all of the above by hand, one step at a time | [`clients/cli/README.md`](clients/cli/README.md) |

## Troubleshooting

`FATAL: connection requires a valid client certificate` almost always
means a wrong/missing `sslcert`/`sslkey` path on the *client* side, not
a real trust problem -- confirmed directly against a live cluster:
libpq does not error when those files don't exist, it silently connects
without presenting a client certificate at all, and Postgres only then
rejects the connection server-side with this message. See
`clients/cli/README.md` step 4's callout before assuming it's a CA/RBAC
issue.
