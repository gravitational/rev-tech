"""Simplest possible call: Ping the Auth Service to confirm connectivity.

Usage (routed through a Teleport Proxy, the default -- see teleport_grpc_client.py):
    python3 ping_example.py --proxy <proxy-host>:443 --cluster-name <cluster> \\
        --key identity.key --cert identity.crt --cas identity.cas

Usage (direct, --direct):
    python3 ping_example.py --direct --proxy <host:port> --tls-server-name <name> \\
        --key identity.key --cert identity.crt --cas identity.cas

Run with --help to see all connection flags and their defaults.
"""
import argparse

from teleport_grpc_client import add_connection_args, build_stub_from_args, check_server_compatibility
from teleport.legacy.client.proto import authservice_pb2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_connection_args(parser)
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
