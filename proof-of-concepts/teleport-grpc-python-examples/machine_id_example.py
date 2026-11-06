"""Call the Teleport Auth Service using a Machine ID (tbot) identity.

The other examples in this folder default to a human-user identity file
(identity.key / identity.crt / identity.cas). This one defaults its --key/
--cert/--cas flags to a Machine ID bot's identity instead -- the
recommended approach for an unattended/automated caller of the Auth API
(cron job, CI pipeline, service, etc).

Setup, verified end-to-end against a local test cluster:

    # 1. Create the bot and a join token for it.
    tctl bots add my-bot --roles=access-request-admin,access

    # 2. Use the printed token to fetch a short-lived identity.
    tbot start identity \\
      --destination=file:///path/to/tbot-identity \\
      --storage=file:///path/to/tbot-storage \\
      --proxy-server=<cluster-proxy-host>:443 \\
      --token=<join-token-from-step-1> \\
      --join-method=token \\
      --oneshot

`tbot`'s directory destination writes several files; the three this
example needs are `key` (private key), `tlscert` (the bot's TLS client
cert), and `teleport-host-ca.crt` (the CA that signed the Auth Service's
own certificate -- this is what the gRPC channel uses to verify the
server, same role `identity.cas` plays for a plain identity file).

In production, run `tbot` as a long-lived process (not `--oneshot`) so it
keeps renewing the identity in the background; this example just reads
whatever's currently on disk.

Usage (routed through a Teleport Proxy, the default -- the realistic case
for most bots, since they usually can't reach Auth's own port; see
teleport_grpc_client.py):
    python3 machine_id_example.py --proxy <cluster-proxy-host>:443 \\
        --cluster-name <cluster> \\
        --key tbot-identity/key --cert tbot-identity/tlscert \\
        --cas tbot-identity/teleport-host-ca.crt

Usage (direct, --direct -- needs network access to Auth's own port):
    python3 machine_id_example.py --direct --proxy <host:port> --tls-server-name <name> \\
        --key tbot-identity/key --cert tbot-identity/tlscert \\
        --cas tbot-identity/teleport-host-ca.crt

Run with --help to see all connection flags and their defaults.
"""
import argparse

from teleport_grpc_client import add_connection_args, build_stub_from_args, check_server_compatibility
from teleport.legacy.client.proto import authservice_pb2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_connection_args(
        parser,
        default_key="tbot-identity/key",
        default_cert="tbot-identity/tlscert",
        default_cas="tbot-identity/teleport-host-ca.crt",
    )
    args = parser.parse_args()

    stub, close = build_stub_from_args(args)
    try:
        resp = stub.Ping(authservice_pb2.PingRequest())
        check_server_compatibility(resp.ServerVersion)
        print(f"cluster:  {resp.ClusterName}")
        print(f"version:  {resp.ServerVersion}")
        print(f"remote:   {resp.RemoteAddr}")
    finally:
        close()


if __name__ == "__main__":
    main()
