"""Approve (or deny) a pending access request over the raw gRPC Auth API.

Equivalent of: tctl requests approve <request-id> --reason "..."

Usage:
    python3 review_access_request_example.py <request-id> --approve \\
        --reason "approved via gRPC example" \\
        --proxy <host:port> --tls-server-name <name> \\
        --key identity.key --cert identity.crt --cas identity.cas

Pair with create_access_request_example.py: run that first, copy the "id:"
it prints, then pass it here. Run with --help to see all connection flags.
"""
import argparse

from teleport_grpc_client import add_connection_args, build_stub_from_args
from teleport.legacy.client.proto import authservice_pb2
from teleport.legacy.types import types_pb2


def review_access_request(stub, request_id: str, approve: bool, delegator: str = "", reason: str = ""):
    state = types_pb2.RequestState.APPROVED if approve else types_pb2.RequestState.DENIED
    stub.SetAccessRequestState(
        authservice_pb2.RequestStateSetter(
            ID=request_id,
            State=state,
            Delegator=delegator,
            Reason=reason,
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_connection_args(parser)
    parser.add_argument("request_id", help="ID of the access request to review")
    decision = parser.add_mutually_exclusive_group()
    decision.add_argument("--approve", action="store_true", help="approve the request (default)")
    decision.add_argument("--deny", action="store_true", help="deny the request")
    parser.add_argument("--reason", default="approved via gRPC example", help="resolve reason (default: %(default)s)")
    parser.add_argument("--delegator", default="api-admin", help="who/what is resolving this (default: %(default)s)")
    args = parser.parse_args()

    stub, close = build_stub_from_args(args)
    try:
        review_access_request(
            stub, args.request_id, approve=not args.deny, delegator=args.delegator, reason=args.reason
        )

        resp = stub.ListAccessRequests(
            authservice_pb2.ListAccessRequestsRequest(
                Filter=types_pb2.AccessRequestFilter(ID=args.request_id)
            )
        )
        if not resp.AccessRequests:
            print(f"Request {args.request_id} not found after review.")
            return
        r = resp.AccessRequests[0]
        print(f"{r.Metadata.Name}  state={types_pb2.RequestState.Name(r.Spec.State)}  resolve_reason={r.Spec.ResolveReason!r}")
    finally:
        close()


if __name__ == "__main__":
    main()
