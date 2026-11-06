"""Create a Teleport Access Request over the raw gRPC Auth API.

Equivalent of: tctl requests create --user=alice --roles=access

Usage (routed through a Teleport Proxy, the default):
    python3 create_access_request_example.py --user alice --roles access \\
        --reason "need temporary access for debugging" \\
        --proxy <proxy-host>:443 --cluster-name <cluster> \\
        --key identity.key --cert identity.crt --cas identity.cas

Run with --help to see all connection flags and their defaults (including
--direct, to connect to Auth's own port instead).
"""
import argparse
import uuid

from teleport_grpc_client import add_connection_args, build_stub_from_args
from teleport.legacy.client.proto import authservice_pb2
from teleport.legacy.types import types_pb2, metadata_pb2


def create_access_request(stub, user: str, roles: list[str], reason: str = ""):
    request = types_pb2.AccessRequestV3(
        Kind="access_request",
        Version="v3",
        # The server assigns its own request ID on creation; this is just a
        # placeholder to satisfy the (non-nullable) Metadata field.
        Metadata=metadata_pb2.Metadata(Name=str(uuid.uuid4())),
        Spec=types_pb2.AccessRequestSpecV3(
            User=user,
            Roles=roles,
            RequestReason=reason,
        ),
    )
    return stub.CreateAccessRequestV2(request)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_connection_args(parser)
    parser.add_argument("--user", default="alice", help="user to request access on behalf of (default: %(default)s)")
    parser.add_argument(
        "--roles", default=["access"], nargs="+", help="role(s) being requested (default: %(default)s)"
    )
    parser.add_argument(
        "--reason", default="need temporary access for debugging", help="request reason (default: %(default)s)"
    )
    args = parser.parse_args()

    stub, close = build_stub_from_args(args)
    try:
        created = create_access_request(stub, user=args.user, roles=args.roles, reason=args.reason)
        print("Created access request:")
        print(f"  id:    {created.Metadata.Name}")
        print(f"  user:  {created.Spec.User}")
        print(f"  roles: {list(created.Spec.Roles)}")
        print(f"  state: {types_pb2.RequestState.Name(created.Spec.State)}")

        # NOTE: the identity used here needs an `allow.rules` entry granting
        # list/read on the "access_request" resource to see it back via
        # ListAccessRequests/GetAccessRequestsV2 -- the built-in "editor" role
        # does not include this by default.
        list_resp = stub.ListAccessRequests(
            authservice_pb2.ListAccessRequestsRequest(
                Filter=types_pb2.AccessRequestFilter(ID=created.Metadata.Name)
            )
        )
        print(f"\nListAccessRequests found {len(list_resp.AccessRequests)} matching request(s)")
    finally:
        close()


if __name__ == "__main__":
    main()
