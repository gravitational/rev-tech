"""List pending access requests over the raw gRPC Auth API.

Equivalent of: tctl requests ls

Usage (routed through a Teleport Proxy, the default):
    python3 list_access_requests_example.py --proxy <proxy-host>:443 --cluster-name <cluster> \\
        --key identity.key --cert identity.crt --cas identity.cas

Run with --help to see all connection flags and their defaults (including
--direct, to connect to Auth's own port instead).
"""
import argparse

from teleport_grpc_client import add_connection_args, build_stub_from_args
from teleport.legacy.client.proto import authservice_pb2
from teleport.legacy.types import types_pb2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_connection_args(parser)
    parser.add_argument("--limit", type=int, default=100, help="max requests to list (default: %(default)s)")
    args = parser.parse_args()

    stub, close = build_stub_from_args(args)
    try:
        resp = stub.ListAccessRequests(authservice_pb2.ListAccessRequestsRequest(Limit=args.limit))

        if not resp.AccessRequests:
            print("No access requests found.")
            return

        for r in resp.AccessRequests:
            print(
                f"{r.Metadata.Name}  user={r.Spec.User}  "
                f"roles={list(r.Spec.Roles)}  "
                f"state={types_pb2.RequestState.Name(r.Spec.State)}  "
                f"reason={r.Spec.RequestReason!r}"
            )
    finally:
        close()


if __name__ == "__main__":
    main()
