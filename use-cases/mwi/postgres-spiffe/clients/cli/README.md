# CLI: get a Workload Identity and do a transaction

This mirrors what the Python and Go clients do in-cluster (see
`../python` and `../go`), but run from your workstation: a human `tsh`
user self-issues the same SPIFFE X.509-SVID directly (no tbot, no join
token needed), `tsh` opens the TCP tunnel through Teleport Application
Access, and `psql` does the transaction over both.

Prerequisites: `tsh` matching your Teleport cluster's version, the
resources in `../../teleport/` applied (`../../setup.sh` does this), and
you've been assigned the `${CLI_ROLE_NAME}` role (see
`../../teleport/role-human-cli.yaml`'s comments for the `tctl users
update` command).

**Run every command below from the same directory.** `./svids` is a
relative path -- if you run step 2 in one terminal and step 4 in
another (likely, since step 3's VNet session needs its own terminal)
from a different working directory, `psql` will fail in a way that
looks like an auth problem but isn't (see the callout in step 4). `cd`
somewhere specific first and stay there for steps 2 and 4.

**The resource names below (`$WORKLOAD_IDENTITY_NAME`, `$APP_NAME`,
etc.) include the random suffix `../../setup.sh` generated into
`../../.env`** -- they are NOT the literal strings shown in
`../../teleport/*.yaml`'s comments. Load the real values into your
shell first:

```bash
set -a && source ../../.env && set +a
```

## 1. Log in to Teleport

```bash
tsh login --proxy=$TELEPORT_PROXY_ADDR
```

## 2. Get your own Workload Identity from the command line

```bash
mkdir -p ./svids
tsh workload-identity issue-x509 \
  --output ./svids \
  --name-selector $WORKLOAD_IDENTITY_NAME \
  --credential-ttl 1h

ls ./svids
# svid.pem  svid_key.pem  svid_bundle.pem
```

No bot, no join token, no waiting on tbot -- this uses your own `tsh`
session directly. `svid_bundle.pem` here is Teleport's Workload Identity
trust bundle; it's also exactly what `../../setup.sh` uses to populate
the `$SPIFFE_CA_SECRET_NAME` secret Postgres trusts (see that script,
or do it by hand: `kubectl create secret generic $SPIFFE_CA_SECRET_NAME
-n $NAMESPACE --from-file=bundle.pem=./svids/svid_bundle.pem`).

## 3. Start VNet to reach Postgres via Teleport TCP Application Access

```bash
tsh vnet
```

Leave this running in its own terminal. VNet sets up a local DNS
resolver + virtual network interface that intercepts connections to
Teleport-protected apps and routes them through Teleport automatically
-- no `tsh apps login`, no local port to keep track of, and (like `tsh
proxy app` before it) still the only network path to Postgres used
anywhere in this demo; there's no direct route to the Kubernetes
Service. While `tsh vnet` is running, the app is reachable at
`$APP_NAME.<proxy-address-without-the-port>` -- `tsh apps ls` also
shows it, if you want to double check. See [Teleport's VNet
docs](https://goteleport.com/docs/connect-your-client/teleport-clients/vnet/)
for more detail on how it works.

## 4. Do the transaction

```bash
psql "host=$APP_NAME.${TELEPORT_PROXY_ADDR%:*} port=5432 dbname=demo user=app_user \
  sslmode=require \
  sslcert=./svids/svid.pem sslkey=./svids/svid_key.pem"
```

(`${TELEPORT_PROXY_ADDR%:*}` is bash's own syntax for "strip the
trailing `:<port>`" -- if your shell doesn't support it, just substitute
your proxy's hostname by hand.)

No `postgres-server-ca.crt` to fetch: `sslmode=require` still forces an
encrypted connection and still presents your SVID as the client
certificate (so Postgres' `cert` auth on the server side works exactly
the same either way) -- it just skips the *client's* optional check of
Postgres' own server identity, which isn't what this demo is
demonstrating and isn't needed on top of Teleport's own access control
already gating who can reach Postgres through VNet at all. If you do
want that extra check (`sslmode=verify-ca`), fetch the CA first:
`kubectl get secret postgres-server-ca -n $NAMESPACE -o
jsonpath='{.data.ca\.crt}' | base64 -d > ./postgres-server-ca.crt`, then
add `sslrootcert=./postgres-server-ca.crt` to the command above.

> **`FATAL: connection requires a valid client certificate`?** This is
> almost always a wrong or missing `sslcert`/`sslkey` path, not a real
> auth problem -- confirmed directly: libpq does **not** error when
> those files don't exist at the given path, it just silently connects
> without presenting a client certificate at all, and Postgres only then
> rejects it server-side with this exact message. Run `ls ./svids` from
> the same shell you're about to run `psql` in -- if it doesn't list
> `svid.pem`/`svid_key.pem`, that's the bug, not Teleport or Postgres.

```sql
BEGIN;
INSERT INTO transactions (account, amount, description)
  VALUES ('wi-demo-cli', 42.00, 'Deposit via Teleport Workload Identity (CLI)')
  RETURNING id;
SELECT id, account, amount, description, created_at FROM transactions ORDER BY id DESC LIMIT 1;
COMMIT;
```

`psql` authenticated with zero passwords: Postgres accepted the
connection because the client certificate was a SPIFFE X.509-SVID signed
by the Workload Identity trust bundle in `ssl_ca_file`, with a Common
Name (`app_user`) matching the requested database role.

## Alternative: plain Teleport Database Access instead of Workload Identity

If you just want a normal `tsh db connect` experience (no SVID files,
no manual TLS flags) rather than demonstrating Workload Identity
specifically, `../../setup.sh` also sets up regular Teleport Database
Access with automatic Postgres user provisioning when
`ENABLE_DB_SERVICE=true` in `../../.env` (the default). With the
`${CLI_ROLE_NAME}-db-access` role assigned:

```bash
tsh login --proxy=$TELEPORT_PROXY_ADDR
tsh db connect --db-name=demo --db-roles=reader,writer $APP_NAME
```

Teleport creates a Postgres login named after your Teleport username on
first connect (see `../../teleport/role-db-access.yaml` and
`../../postgres-chart/values.yaml`'s `03-teleport-db-service.sql`) --
you never touch a certificate file directly, and you're not sharing
`app_user` with every other client in this demo. You land in a normal
`psql` prompt, already `\connect`ed to `demo` -- try the same
transaction the other clients do:

```sql
BEGIN;
INSERT INTO transactions (account, amount, description)
  VALUES ('wi-demo-dbaccess', 42.00, 'Deposit via Teleport Database Access')
  RETURNING id;
SELECT id, account, amount, description, created_at FROM transactions ORDER BY id DESC LIMIT 1;
COMMIT;

-- Confirm it's really you, not "app_user" or anyone else:
SELECT current_user;
```
