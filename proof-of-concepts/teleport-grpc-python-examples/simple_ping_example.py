"""The simplest possible example: ping Teleport's Auth Service from Python.

No command-line flags, no required setup -- if you're in an active
`tsh login` shell, this just works as-is: it reads your tsh profile
(proxy, cluster, and credentials) straight from $TSH_HOME (or ~/.tsh).

Otherwise, set TELEPORT_PROXY / TELEPORT_CLUSTER and drop identity.key /
identity.crt / identity.cas in this same folder -- see README.md
"Quick start" for how to get those (e.g. from a Machine ID bot via `tbot`).

Note: if TELEPORT_PROXY/TELEPORT_CLUSTER are already set in your shell to
something else (some environments export these globally), they'll win
over your tsh profile -- `unset` them first if that's not what you want.

Run:

    python3 simple_ping_example.py
"""
import os

from teleport_grpc_client import resolve_connection, build_stub_via_proxy, build_stub, check_server_compatibility
from teleport.legacy.client.proto import authservice_pb2

proxy, cluster, key, cert, cas, via_proxy = resolve_connection(
    proxy=os.environ.get("TELEPORT_PROXY"),
    cluster=os.environ.get("TELEPORT_CLUSTER"),
)

if via_proxy:
    stub, relay = build_stub_via_proxy(proxy, cluster, key, cert, cas)
else:
    stub, relay = build_stub(proxy, cluster or proxy.split(":")[0], key, cert, cas), None

try:
    resp = stub.Ping(authservice_pb2.PingRequest())
    check_server_compatibility(resp.ServerVersion)
    print(f"Connected to Teleport cluster {resp.ClusterName!r} (v{resp.ServerVersion})")
finally:
    if relay is not None:
        relay.close()
