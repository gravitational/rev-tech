"""Shared helper for connecting to Teleport's Auth Service gRPC API.

Every example script in this folder takes the same connection flags (run
any of them with --help to see this exact list):

    --proxy             host:port to connect to (a Proxy, by default).
    --cluster-name      the cluster's name, required by default (see below).
    --direct            connect to the Auth Service's own port directly
                         instead of routing through a Proxy.
    --tls-server-name   SAN on the auth server's host cert; --direct mode
                         only. Default: local-test
    --key               path to the identity's private key.
    --cert              path to the identity's client certificate.
    --cas               path to the CA(s) used to verify the auth server.

Routing through a Proxy is the default -- that's the realistic topology
for most real clusters (see "Connecting through a Proxy" below). Pass
--direct to connect to Auth's own port instead.

--key/--cert/--cas point at whatever identity you got from `tbot` (Machine
ID) or a human user identity file -- see README.md "Quick start." Relative
paths are resolved from this folder; absolute paths work as-is.

## Two ways to connect

**Via proxy** (default): most real clusters only expose the Proxy
publicly (e.g. port 443), not the Auth Service's own port. Teleport routes
different protocols through that single port using the TLS ClientHello's
ALPN extension ("TLS Routing") -- e.g. Teleport's own Go tooling offers the
ALPN protocol `teleport-auth@<hex-encoded-cluster-name>.teleport.cluster.local`
to tell the Proxy "forward this connection's raw bytes to the Auth
Service," then completes a normal mTLS handshake with Auth over that
forwarded byte stream.

`grpc-python` has no public API to set a custom ALPN protocol list (unlike
Go's grpc, which lets a caller fully control the transport via
`grpc.WithContextDialer`) -- see README.md for why. So `build_stub_via_proxy()`
does the ALPN+TLS handshake itself with Python's `ssl` module, then relays
grpc's plaintext HTTP/2 bytes into that already-authenticated connection
over a local loopback socket. The entire mechanism runs in this process --
no cluster-side configuration (no Application Access resource, nothing)
and no dependency on `tsh`/`tctl` at runtime. It was derived by reading
Teleport's own source (api/constants, lib/srv/alpnproxy/auth) and verified
against both a local test cluster and a real one.

One cert-verification subtlety: the SNI sent during the handshake must be
the Proxy's own public hostname (that's what the Proxy's router keys off
to decide where to forward bytes), but the Auth Service's host certificate
is issued for Teleport's fixed internal domain (`teleport.cluster.local`),
not the Proxy's public hostname. So hostname verification has to check
against `teleport.cluster.local` specifically, decoupled from the SNI value
-- this is the same split Teleport's own Go client makes internally. The
certificate chain itself is still fully validated against the real Auth
host CA; nothing about trust is weakened, the verification target is just
different from the SNI value.

**Direct** (--direct): dial the Auth Service's own listening port
directly. Needs network-level access to that port (on-prem/same-host/VPN
setups) -- the exception, not the rule, for most real clusters. Simple
mTLS, nothing clever -- `build_stub()`.
"""
import argparse
import os
import socket
import ssl
import sys
import threading
import types

GEN_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen", "python")
sys.path.insert(0, GEN_DIR)

import grpc  # noqa: E402
from teleport.legacy.client.proto import authservice_pb2_grpc  # noqa: E402

# Teleport's fixed internal API domain. Auth Service host certs always
# carry this as a SAN so clients can verify them independent of the
# server's real address. See gravitational/teleport api/constants/constants.go.
TELEPORT_API_DOMAIN = "teleport.cluster.local"


def add_connection_args(
    parser: argparse.ArgumentParser,
    default_key: str = "identity.key",
    default_cert: str = "identity.crt",
    default_cas: str = "identity.cas",
) -> argparse.ArgumentParser:
    """Adds the connection flags shared by every example.

    Routing through a Teleport Proxy is the default -- that's the
    realistic topology for most real clusters (see README.md "Connecting
    through a Proxy"). Pass --direct to connect to the Auth Service's own
    port instead.
    """
    group = parser.add_argument_group("Teleport connection")
    group.add_argument(
        "--proxy",
        default=None,
        help="host:port to connect to (Proxy by default, Auth's own port with --direct; "
        "falls back to your active tsh profile if omitted)",
    )
    group.add_argument(
        "--cluster-name",
        default=None,
        help="cluster name; required unless --direct or an active tsh profile supplies it",
    )
    group.add_argument(
        "--direct",
        action="store_true",
        help="connect to the Auth Service's own port directly instead of routing through a Proxy",
    )
    group.add_argument(
        "--tls-server-name",
        default="local-test",
        help="SAN on the auth server's host certificate; --direct mode only (default: %(default)s)",
    )
    group.add_argument(
        "--key",
        default=default_key,
        help="path to the identity's private key (default: %(default)s)",
    )
    group.add_argument(
        "--cert",
        default=default_cert,
        help="path to the identity's client certificate (default: %(default)s)",
    )
    group.add_argument(
        "--cas",
        default=default_cas,
        help="path to the CA(s) used to verify the auth server (default: %(default)s)",
    )
    return parser


def _resolve(base: str, path: str) -> str:
    return os.path.join(base, path)


def build_stub(
    auth_addr: str = "127.0.0.1:3025",
    tls_server_name: str = "local-test",
    identity_key: str = "identity.key",
    identity_cert: str = "identity.crt",
    identity_cas: str = "identity.cas",
) -> authservice_pb2_grpc.AuthServiceStub:
    """Direct connection to the Auth Service's own port. See module docstring."""
    base = os.path.dirname(os.path.abspath(__file__))
    with open(_resolve(base, identity_key), "rb") as f:
        key = f.read()
    with open(_resolve(base, identity_cert), "rb") as f:
        cert = f.read()
    with open(_resolve(base, identity_cas), "rb") as f:
        ca = f.read()

    creds = grpc.ssl_channel_credentials(root_certificates=ca, private_key=key, certificate_chain=cert)
    channel = grpc.secure_channel(
        auth_addr,
        creds,
        options=(("grpc.ssl_target_name_override", tls_server_name),),
    )
    return authservice_pb2_grpc.AuthServiceStub(channel)


def _alpn_auth_protocol(cluster_name: str) -> str:
    # Mirrors api/utils.EncodeClusterName + the "teleport-auth@" prefix from
    # api/constants.ALPNSNIAuthProtocol.
    return "teleport-auth@" + cluster_name.encode().hex() + "." + TELEPORT_API_DOMAIN


def _verify_dns_san(cert: dict, expected: str) -> None:
    for typ, value in cert.get("subjectAltName", ()):
        if typ != "DNS":
            continue
        if value == expected or (value.startswith("*.") and expected.endswith(value[1:])):
            return
    raise ssl.SSLCertVerificationError(f"server certificate has no DNS SAN matching {expected!r}")


def _relay(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass


class ProxyRoutedChannel:
    """Owns the ALPN-routed connection to Auth (via the Proxy) and the local
    loopback relay that lets grpc-python talk to it. Call close() when done.
    """

    def __init__(self, proxy_addr: str, cluster_name: str, key_path: str, cert_path: str, ca_path: str):
        host, port = proxy_addr.rsplit(":", 1)

        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.load_verify_locations(cafile=ca_path)
        ctx.load_cert_chain(certfile=cert_path, keyfile=key_path)
        ctx.set_alpn_protocols([_alpn_auth_protocol(cluster_name), "h2"])
        ctx.check_hostname = False  # verified manually below, against the correct target (see module docstring)

        sock = socket.create_connection((host, int(port)), timeout=10)
        # SNI must be the proxy's own hostname -- that's what its router keys off.
        self._remote = ctx.wrap_socket(sock, server_hostname=host)
        _verify_dns_san(self._remote.getpeercert(), TELEPORT_API_DOMAIN)

        self._listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._listener.bind(("127.0.0.1", 0))
        self._listener.listen(1)
        self.local_port = self._listener.getsockname()[1]
        self._local: socket.socket | None = None

        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self) -> None:
        conn, _ = self._listener.accept()
        self._local = conn
        threading.Thread(target=_relay, args=(conn, self._remote), daemon=True).start()
        threading.Thread(target=_relay, args=(self._remote, conn), daemon=True).start()

    def close(self) -> None:
        for s in (self._local, self._remote, self._listener):
            try:
                if s is not None:
                    s.close()
            except OSError:
                pass


def build_stub_via_proxy(
    proxy_addr: str,
    cluster_name: str,
    identity_key: str = "identity.key",
    identity_cert: str = "identity.crt",
    identity_cas: str = "identity.cas",
) -> tuple[authservice_pb2_grpc.AuthServiceStub, ProxyRoutedChannel]:
    """Connection to Auth routed through a Teleport Proxy. See module docstring.

    Returns (stub, relay) -- call relay.close() when done with the stub.
    """
    base = os.path.dirname(os.path.abspath(__file__))
    relay = ProxyRoutedChannel(
        proxy_addr,
        cluster_name,
        _resolve(base, identity_key),
        _resolve(base, identity_cert),
        _resolve(base, identity_cas),
    )
    channel = grpc.insecure_channel(f"127.0.0.1:{relay.local_port}")
    return authservice_pb2_grpc.AuthServiceStub(channel), relay


def tsh_profile_identity() -> types.SimpleNamespace | None:
    """Reads the active `tsh` profile from $TSH_HOME (or ~/.tsh), tsh's own
    on-disk layout -- no tsh dependency at runtime, just its plain files.
    Returns None if there's no active profile or its key files are missing
    (e.g. a hardware-backed/PIV key with no exportable private key -- that's
    a real limitation some environments hit, not something this detects).
    """
    tsh_home = os.environ.get("TSH_HOME") or os.path.expanduser("~/.tsh")
    try:
        with open(os.path.join(tsh_home, "current-profile")) as f:
            proxy_host = f.read().strip()
        with open(os.path.join(tsh_home, f"{proxy_host}.yaml")) as f:
            profile = dict(line.split(":", 1) for line in f if ":" in line)
        profile = {k.strip(): v.strip() for k, v in profile.items()}
        proxy_addr = profile["web_proxy_addr"]
        user = profile["user"]
        cluster = profile["cluster"]
    except (FileNotFoundError, KeyError):
        return None

    keys_dir = os.path.join(tsh_home, "keys", proxy_host)
    key_path = os.path.join(keys_dir, f"{user}.key")
    cert_path = os.path.join(keys_dir, f"{user}.crt")
    cas_path = os.path.join(keys_dir, "certs.pem")
    if not all(os.path.exists(p) for p in (key_path, cert_path, cas_path)):
        return None

    return types.SimpleNamespace(
        proxy_addr=proxy_addr, cluster=cluster, key_path=key_path, cert_path=cert_path, cas_path=cas_path
    )


def pinned_teleport_version() -> str | None:
    """Returns the Teleport version gen/python was compiled from, read from
    gen/TELEPORT_VERSION (written by generate_stubs.sh), or None if missing.
    """
    base = os.path.dirname(os.path.abspath(__file__))
    try:
        with open(os.path.join(base, "gen", "TELEPORT_VERSION")) as f:
            return f.read().strip().lstrip("v")
    except FileNotFoundError:
        return None


def check_server_compatibility(server_version: str) -> None:
    """Warns on stderr (does not raise) if the live server's major version
    is too far from the Teleport version gen/python was generated from.

    Teleport documents limited client/server version skew support, but
    these are raw generated proto stubs, not a version-negotiating client
    -- there's no runtime compatibility shim protecting you here, so a
    large divergence is worth a human looking at rather than a cryptic
    failure three calls later. Call this after any RPC that returns a
    server version (e.g. Ping).
    """
    pinned = pinned_teleport_version()
    if not pinned:
        return
    try:
        pinned_major = int(pinned.split(".")[0])
        server_major = int(server_version.split(".")[0])
    except (ValueError, IndexError):
        return
    if abs(pinned_major - server_major) > 1:
        print(
            f"WARNING: gen/python was generated from Teleport v{pinned}, but the "
            f"server is running v{server_version} (major version delta: "
            f"{abs(pinned_major - server_major)}). RPCs or message fields may have "
            f"changed -- see README.md 'Versioning & upgrading' before trusting results.",
            file=sys.stderr,
        )


def resolve_connection(
    proxy: str | None,
    cluster: str | None,
    key: str = "identity.key",
    cert: str = "identity.crt",
    cas: str = "identity.cas",
    via_proxy: bool = True,
):
    """Falls back to the active `tsh` profile under $TSH_HOME (or ~/.tsh)
    whenever the --key/--cert/--cas files don't exist locally -- so a script
    with no identity configured at all just works if you're already
    `tsh login`'d. Explicit proxy/cluster arguments still win over the tsh
    profile's values. Returns (proxy, cluster, key, cert, cas, via_proxy).
    """
    base = os.path.dirname(os.path.abspath(__file__))
    identity_found = all(os.path.exists(_resolve(base, p)) for p in (key, cert, cas))
    if not identity_found:
        tsh = tsh_profile_identity()
        if tsh is None:
            raise SystemExit(
                f"No identity found at {key}/{cert}/{cas}, and no active tsh profile "
                f"under $TSH_HOME (or ~/.tsh). Provide an identity, or `tsh login` first."
            )
        print(f"No local identity files; using active tsh profile ({tsh.proxy_addr}, cluster {tsh.cluster})", file=sys.stderr)
        key, cert, cas = tsh.key_path, tsh.cert_path, tsh.cas_path
        proxy = proxy or tsh.proxy_addr
        cluster = cluster or tsh.cluster
        # A tsh profile's address is the Proxy, essentially always -- not Auth's own port.
        via_proxy = True
    return proxy, cluster, key, cert, cas, via_proxy


def build_stub_from_args(args: argparse.Namespace):
    """Pairs with add_connection_args(): build_stub_from_args(parser.parse_args()).

    Via-proxy is the default (pass --direct to opt out). See
    resolve_connection() for the tsh-profile fallback behavior -- note that
    a tsh-derived identity always forces via-proxy mode, even with
    --direct, since a tsh profile's address is essentially always a Proxy.

    Always returns (stub, close) -- call close() when done with the stub
    (a no-op in direct mode, where there's nothing of ours to tear down).
    """
    proxy, cluster, key, cert, cas, via_proxy = resolve_connection(
        args.proxy, args.cluster_name, args.key, args.cert, args.cas, via_proxy=not args.direct
    )

    if via_proxy:
        if not proxy:
            raise SystemExit("--proxy is required in via-proxy mode (or an active tsh profile)")
        if not cluster:
            raise SystemExit("--cluster-name is required in via-proxy mode (or an active tsh profile)")
        stub, relay = build_stub_via_proxy(
            proxy_addr=proxy,
            cluster_name=cluster,
            identity_key=key,
            identity_cert=cert,
            identity_cas=cas,
        )
        return stub, relay.close

    stub = build_stub(
        auth_addr=proxy or "127.0.0.1:3025",  # implicit default for local-test convenience
        tls_server_name=args.tls_server_name,
        identity_key=key,
        identity_cert=cert,
        identity_cas=cas,
    )
    return stub, (lambda: None)
