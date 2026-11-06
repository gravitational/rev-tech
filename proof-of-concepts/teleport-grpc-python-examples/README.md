# Teleport Auth Service — Python gRPC Examples

Teleport's control plane (the Auth Service) is a gRPC server. Everything
`tctl`/`tsh` do — pinging the cluster, managing access requests, users,
roles, nodes, etc. — happens over that gRPC API. Teleport doesn't ship an
official Python client for it, but since it's just gRPC + protobuf, you can
generate your own bindings from Teleport's open-source `.proto` files and
call it directly from Python.

This folder does exactly that: compiles real stubs from
[gravitational/teleport](https://github.com/gravitational/teleport)'s
`api/proto`, and uses them to call `AuthService` — the same service
`tctl`/`tsh` talk to — for a few common operations.

Every script here was run against a real Teleport cluster before being
committed — both a disposable local test cluster and a real one, over
both connection modes described below. This isn't "should work" sample
code; every claim in this README was checked against a live Auth Service.

## How it fits together

```mermaid
flowchart LR
    subgraph "One-time setup (pinned Teleport version)"
        A["gravitational/teleport\n*.proto files\n@ pinned release tag"] -->|generate_stubs.sh\ngrpc_tools.protoc| B["gen/python/\n*_pb2.py, *_pb2_grpc.py"]
    end

    subgraph "Per-call"
        C["Identity\n(key + cert + CA)\nissued to a user or a\nMachine ID bot"] --> D["teleport_grpc_client.py"]
        B --> D
        D -->|"default: ALPN-routed\nmTLS, in-process relay"| G["Teleport\nProxy"]
        G -.->|TLS Routing| E
        D -->|"--direct: plain mTLS"| E["Teleport\nAuth Service"]
    end

    F["ping_example.py\ncreate_access_request_example.py\nlist_access_requests_example.py\nreview_access_request_example.py\nmachine_id_example.py"] --> D
```

- **Proto → Python** happens once (or whenever you deliberately bump the
  pinned Teleport version — see "Versioning & upgrading" below).
  `generate_stubs.sh` fetches the `.proto` definitions at that version and
  compiles them into `gen/python/`.
- **Identity** is an mTLS client certificate issued by the cluster. It can
  belong to a human user, or (the recommended approach for
  unattended/automated callers) a **Machine ID bot** managed by `tbot`.
  Either way, it's the same three things: a private key, a client
  certificate, and the CA to trust the server with.
- **Connection mode** defaults to routing through a Teleport Proxy — the
  way most real deployments require — with `--direct` to opt out and dial
  the Auth Service's own port instead. See the dedicated section below —
  this isn't a minor detail, it took real work to get right.
- **Each example script** builds a gRPC stub this way and calls one RPC on
  `AuthService`.

## Connecting through a Proxy (the default)

Most real Teleport clusters only expose the Proxy publicly (e.g. port
443) — not the Auth Service's own listening port. A pure Python gRPC
client reaching Auth *through* that proxy turned out to be the hard part
of this whole exercise, worth documenting properly rather than glossing
over.

**Why `grpc-python` can't just dial the proxy normally:** Teleport routes
different protocols (SSH, Postgres, Kubernetes, Auth API, ...) through
that single public port using the TLS ClientHello's ALPN extension — a
technique Teleport calls "TLS Routing." To reach Auth specifically, the
client has to offer the ALPN protocol
`teleport-auth@<hex-encoded-cluster-name>.teleport.cluster.local`
(derived from `api/constants.ALPNSNIAuthProtocol` and
`api/utils.EncodeClusterName` in Teleport's source) so the Proxy's router
knows to forward the raw bytes to Auth rather than treating it as a
generic web/API request. Teleport's own Go tooling (`tsh`, `tctl`, the
Go API client) can do this because `grpc-go` lets a caller fully own the
transport (`grpc.WithContextDialer`) — the Go code does its own TLS+ALPN
handshake, then hands the resulting connection to `grpc-go`.
**`grpc-python` has no equivalent public hook.** It's a Cython binding
onto grpc's C-core, which owns the entire TCP+TLS lifecycle internally;
there's no documented channel option to set a custom ALPN protocol list.

**What `teleport_grpc_client.py` does about it:** performs that TLS+ALPN
handshake itself with Python's `ssl` module (which *does* expose ALPN
control), then relays grpc's plaintext HTTP/2 bytes into that
already-authenticated connection over a local loopback socket that
`grpc.insecure_channel` connects to. Entirely in-process — no cluster-side
configuration, no `tsh`/`tctl` subprocess, no external relay tool.

```mermaid
sequenceDiagram
    participant Py as Python process
    participant Relay as in-process loopback relay
    participant Proxy as Teleport Proxy :443
    participant Auth as Teleport Auth Service

    Note over Py,Proxy: ssl module, not grpc -- grpc can't set ALPN
    Py->>Proxy: TLS ClientHello, ALPN=[teleport-auth@<hex-cluster>.teleport.cluster.local, h2]
    Proxy->>Auth: forwards raw bytes (SNI/ALPN routing, no TLS termination)
    Auth-->>Py: ServerHello + cert (ALPN negotiates down to h2)
    Note over Py: mTLS now established end-to-end with Auth itself
    Py->>Relay: grpc.insecure_channel("127.0.0.1:<local_port>")
    Relay->>Auth: relays plaintext HTTP/2 bytes over the TLS session above
    Auth-->>Relay: AuthService RPC response
    Relay-->>Py: ...relayed back to the grpc stub
```

One cert-verification subtlety, spelled out here because it's easy to get
wrong: the TLS SNI sent during the handshake must be the **Proxy's own
public hostname** (that's what its router keys off to decide where to
forward bytes), but the certificate that actually comes back is the
**Auth Service's host certificate**, issued for Teleport's fixed internal
domain `teleport.cluster.local` — not the Proxy's hostname. So hostname
verification has to target `teleport.cluster.local`, decoupled from the
SNI value used for routing. The certificate chain itself is still fully
validated against the real Auth host CA the whole time; nothing about
trust is weakened, the verification target is just different from the
SNI. This is the same split Teleport's own Go client makes internally.

**Caveat:** this derives the ALPN protocol scheme and SNI/hostname split
by reading Teleport's source (`api/constants`,
`lib/srv/alpnproxy/auth/auth_proxy.go`) — it isn't a published, versioned
client API contract the way the `.proto` files are. It could change in a
future Teleport release without notice. Re-verify after bumping
`TELEPORT_VERSION` (see "Versioning & upgrading"), same as everything
else generated/derived from source in this folder.

### Access request lifecycle (what most of the examples walk through)

```mermaid
sequenceDiagram
    participant Py as Python client
    participant Auth as Teleport Auth Service

    Py->>Auth: CreateAccessRequestV2(user=alice, roles=[access])
    Auth-->>Py: AccessRequestV3 { id, state: PENDING }

    Py->>Auth: ListAccessRequests(filter={id})
    Auth-->>Py: [ AccessRequestV3 { state: PENDING } ]

    Py->>Auth: SetAccessRequestState(id, state: APPROVED)
    Auth-->>Py: Empty

    Py->>Auth: ListAccessRequests(filter={id})
    Auth-->>Py: [ AccessRequestV3 { state: APPROVED } ]
```

## Folder contents

| File | What it does |
|---|---|
| `requirements.txt` | The one runtime dependency (`grpcio`). `pip3 install -r requirements.txt`. |
| `generate_stubs.sh` | Pulls Teleport's `.proto` files (at a pinned version) + deps and compiles them to `gen/python/`. |
| `gen/python/` | Generated output (checked in so the examples run without a network dependency; see below for why). |
| `gen/TELEPORT_VERSION` | Which Teleport release tag `gen/python/` was generated from. |
| `teleport_grpc_client.py` | Shared helper: builds an mTLS-authenticated `AuthServiceStub`, routed through a Proxy by default or directly with `--direct` (see above). Also the shared argparse connection flags every example uses. |
| `ping_example.py` | Connectivity check — `AuthService.Ping`. |
| `create_access_request_example.py` | Creates a pending access request (`CreateAccessRequestV2`), then confirms it exists (`ListAccessRequests`). |
| `list_access_requests_example.py` | Lists all access requests (`tctl requests ls` equivalent). |
| `review_access_request_example.py` | Approves (or denies) a request by ID (`SetAccessRequestState`). |
| `machine_id_example.py` | Same `Ping` call, but authenticated as a Machine ID bot via `tbot` instead of a user identity. |

## Quick start

### Prerequisites

```bash
pip3 install -r requirements.txt
```

That's `grpcio` and `protobuf` — the two runtime dependencies (the
generated `gen/python/*_pb2.py` files import `google.protobuf` directly;
it's not a guaranteed transitive dependency of plain `grpcio`, so it's
listed explicitly rather than relying on something else happening to pull
it in). `generate_stubs.sh` also needs `grpcio-tools`, but only if you're
regenerating `gen/python/` yourself; it installs that itself.

**If `python3`/`pip3` on your machine is a Homebrew-managed Python**
(check with `python3 -c "import sys; print(sys.executable)"` — Homebrew's
is typically under `/opt/homebrew/...`), a plain `pip install` will
likely refuse with an "externally managed environment" error (PEP 668).
Don't reach for `--break-system-packages` for this — use a virtualenv
instead, which sidesteps the problem entirely and is the generally
correct way to run Python scripts with their own dependencies regardless
of this specific error:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python3 simple_ping_example.py   # use .venv/bin/python3 for every script below
```

### 0. Already `tsh login`'d? Just run it.

If you're in a shell with an active `tsh` session, every script here
falls back to reading that profile directly from `$TSH_HOME` (or
`~/.tsh`) — the same plain files `tsh` itself writes — whenever
`identity.key`/`.crt`/`.cas` aren't present locally. No flags needed:

```bash
python3 simple_ping_example.py
```

This reads your proxy address, cluster name, and credentials straight
from the profile and connects through the proxy (the default mode — a
tsh profile's address is the Proxy, essentially always). If
`TELEPORT_PROXY`/`TELEPORT_CLUSTER` happen to already be set in your
shell to something else, those win — `unset` them first if that's not
what you want.

One real limitation, not a bug: if your tsh identity uses a
hardware-backed key (PIV/YubiKey — some environments enforce this), there
is no raw private key to read, and this fails with a clear error. That's
inherent to this environment's security policy, not something a Python
TLS library can work around — see "Connecting through a Proxy" above for
why Go's tooling doesn't hit this (it uses `crypto.Signer`, a pluggable
signing interface Python's `ssl` module has no equivalent for). Use a
Machine ID bot (Option A below) instead; those always have a software key.

Everything below is for when you want to be explicit about which
identity to use (e.g. Machine ID) rather than relying on your current
session.

### 1. Get an identity (your mTLS credentials)

Every example authenticates via an identity: a private key + client
certificate + CA chain. You have two options:

**Option A — Machine ID (recommended, and what `machine_id_example.py` is
built around).** This is how an automated/unattended caller should get
credentials. A cluster administrator creates a bot and a one-time join
token:

```bash
tctl bots add my-bot --roles=access-request-admin,access
```

Then, using the join token that command prints, fetch a short-lived
identity:

```bash
tbot start identity \
  --destination=file:///path/to/tbot-identity \
  --storage=file:///path/to/tbot-storage \
  --proxy-server=<cluster-proxy-host>:443 \
  --token=<join-token-from-above> \
  --join-method=token \
  --oneshot
```

This writes several files into the destination directory. The three
`machine_id_example.py` reads are `key`, `tlscert`, and
`teleport-host-ca.crt` (the CA that signed the Auth Service's own
certificate). In production, drop `--oneshot` and run `tbot` as a
long-lived process so it keeps renewing the identity in the background.

**Option B — a human user's identity.** If you're testing interactively,
any mechanism your cluster admin provides for issuing a user identity file
works the same way — it's still just a key/cert/CA triple, and
`teleport_grpc_client.py` doesn't care how it was produced.

Whichever option you use, the RBAC gotcha below applies to it.

The identity's roles need appropriate RBAC. One gotcha worth knowing:

- **Creating** an access request doesn't require a special grant — it's
  essentially always available to an authenticated identity.
- **Listing/reading** access requests over gRPC (`ListAccessRequests`,
  `GetAccessRequestsV2`) silently returns *zero results* — no error — if
  the caller's roles don't grant `list`/`read` on the `access_request`
  resource. The built-in `editor` preset role does **not** include this.
  Give your identity a role like:

  ```yaml
  kind: role
  version: v7
  metadata:
    name: access-request-admin
  spec:
    allow:
      rules:
      - resources: [access_request]
        verbs: [list, read, create, update, delete]
  ```

### 2. (Re)generate the Python stubs (optional — already included)

```bash
./generate_stubs.sh
```

Only needed if you're bumping the pinned Teleport version (see below) or
adding RPCs beyond what's already compiled into `gen/python/` (unlikely —
`generate_stubs.sh` already compiles all of `api/proto`, not just
`AuthService`).

### 3. Pick a connection mode

Every example takes the same connection flags (`--help` on any of them
shows the full list).

**Via proxy (default)** — the realistic case for most deployments,
including any Machine ID bot that only has network access to the public
Proxy (see "Connecting through a Proxy" above):

```bash
python3 ping_example.py --proxy <proxy-host>:443 --cluster-name <cluster> \
  --key identity.key --cert identity.crt --cas identity.cas
```

**Direct (`--direct`)** — you have network-level access to the Auth
Service's own port (on-prem, same host, VPN):

```bash
python3 ping_example.py --direct --proxy <auth-host>:3025 --tls-server-name <nodename> \
  --key identity.key --cert identity.crt --cas identity.cas
```

`--cluster-name` (default mode) is the cluster's name as Teleport knows
it, used to build the ALPN routing protocol string. `--tls-server-name`
(`--direct` mode) must match a SAN on the Auth Service's host certificate
(its nodename, by default) — if you see `UNAUTHENTICATED: Hostname
Verification Check failed`, this is the fix.

### 4. Run the examples

```bash
python3 ping_example.py --proxy <proxy-host>:443 --cluster-name <cluster> ...
python3 machine_id_example.py --proxy <proxy-host>:443 --cluster-name <cluster> ...

python3 create_access_request_example.py --proxy <proxy-host>:443 --cluster-name <cluster> ...
# -> prints a request id

python3 list_access_requests_example.py --proxy <proxy-host>:443 --cluster-name <cluster> ...

python3 review_access_request_example.py <request-id> --proxy <proxy-host>:443 --cluster-name <cluster> ...
```

(Add `--direct` and swap `--proxy`/`--cluster-name` for
`--proxy`/`--tls-server-name` for direct mode.)

## Versioning & upgrading

**`generate_stubs.sh` is pinned to a specific Teleport release tag**
(`TELEPORT_VERSION` at the top of the script, currently `v18.10.0` — the
version these examples were last verified against), not whatever is
currently on `master`. This is deliberate, not an oversight:

- Teleport's proto definitions change between releases — fields get added,
  RPCs get deprecated or renamed, whole services get introduced. Pinning
  means regenerating the stubs is a conscious, reviewable action (the diff
  shows exactly what changed) rather than a silent moving target that
  could change out from under you on an unrelated commit.
- Because `gen/python/` is checked in, "what version is this built
  against" is always answered by `gen/TELEPORT_VERSION` — no need to
  re-derive it.

**If you upgrade:**

1. Bump `TELEPORT_VERSION` in `generate_stubs.sh` to the new tag.
2. Re-run `./generate_stubs.sh`.
3. **Re-run every example script against a real cluster before
   committing.** A stub set that compiles cleanly can still fail at
   runtime — a field might get renamed, a request message's required
   fields might change, an RPC might be deprecated in favor of a new one.
   Compilation succeeding only proves the `.proto` syntax is valid, not
   that these examples still call it correctly.
4. Commit the diff in `gen/python/` (and the new `gen/TELEPORT_VERSION`)
   as its own reviewable change, separate from any example-code changes.

As a rule of thumb, keep the pinned version reasonably close to the
Teleport version your actual cluster runs — Teleport generally supports
limited client/server version skew (see Teleport's own compatibility
docs), but these are raw proto definitions, not a version-negotiating
client, so there's no runtime compatibility shim protecting you if you
pin something wildly newer or older than your cluster.

**Automatic check, not just a rule of thumb to remember:** every example
that calls `Ping` also calls `teleport_grpc_client.check_server_compatibility()`
with the live server's version from the response. It compares that
against `gen/TELEPORT_VERSION` and prints a warning to stderr (not a hard
failure — the call already succeeded) if the major versions differ by
more than 1. It won't catch everything (a single-major-version bump can
still rename a field), but it turns the common case of "I forgot to
regenerate stubs after upgrading the cluster" into a visible warning
instead of a confusing failure three calls later.

## Trying it against a disposable local cluster

You don't need a shared cluster to try this — a single `teleport` binary
can run a throwaway auth-only cluster:

```bash
curl -sL -o teleport.tar.gz \
  https://cdn.teleport.dev/teleport-v18.10.0-linux-amd64-bin.tar.gz
tar xzf teleport.tar.gz

cat > teleport.yaml <<'EOF'
version: v3
teleport:
  nodename: local-test
  data_dir: ./data
auth_service:
  enabled: "yes"
  cluster_name: local-test-cluster
  listen_addr: 127.0.0.1:3025
  proxy_listener_mode: multiplex
proxy_service:
  enabled: "yes"
  web_listen_addr: 127.0.0.1:3080
ssh_service:
  enabled: "no"
EOF

./teleport/teleport start --config=teleport.yaml &

# create a role with the RBAC rule from "Quick start" above, then use
# tctl/tbot (both in the same tarball) to get an identity as shown above.
```

(If you're running this inside a Teleport Beams sandbox, `unset
TELEPORT_AUTH_SERVER TELEPORT_PROXY TELEPORT_CLUSTER` first — those env
vars point `tctl`/`tbot` at the *real* cluster and collide with a local
one.)

## Expanding this to other RPCs

`AuthService` (in `gen/python/teleport/legacy/client/proto/`) is Teleport's
original, monolithic gRPC service and covers most day-to-day operations —
users, roles, tokens, sessions, locks, MFA, and more, in addition to access
requests. To find another RPC to call:

1. Look through `api/proto/teleport/legacy/client/proto/authservice.proto`
   (fetch a fresh copy, or re-run `generate_stubs.sh` which clones it into
   a temp dir) for the `rpc` you want on the `AuthService` definition.
2. Find its request/response message types — usually in the same file or
   in `api/proto/teleport/legacy/types/types.proto`.
3. Call it the same way the examples do:
   `stub.<RpcName>(<request_message>(...))`.

Teleport has also been moving newer functionality into smaller,
resource-specific services under `teleport/<resource>/v1/` (e.g.
`teleport/users/v1`, `teleport/loginrule/v1`) instead of growing
`AuthService` further. Those follow the same compile-and-call pattern —
`generate_stubs.sh` already compiles all of `api/proto`, so their stubs
are already sitting in `gen/python/teleport/<resource>/v1/`.

## Caveats

- These are raw, low-level gRPC calls — no retry/backoff, no pagination
  handling beyond what's shown, no MFA-challenge handling. Treat this as a
  foundation to build on, not a full-featured client.
- The default (proxy-routed) mode relies on Teleport's internal ALPN
  routing scheme, derived from source rather than a published API
  contract — see the caveat in "Connecting through a Proxy" above.
- `gen/python/` is ~8 MB of generated code. Regenerate it with
  `generate_stubs.sh`, don't hand-edit it.
