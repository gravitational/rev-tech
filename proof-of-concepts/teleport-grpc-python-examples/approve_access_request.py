"""Approve (or deny) a pending access request -- the same call `tsh request
approve`/`tsh request deny` make.

This calls `AuthService.SubmitAccessReview`, not `SetAccessRequestState`
(see review_access_request_example.py for that one). They are not
interchangeable:

- `SubmitAccessReview` is what a *reviewer* does: it submits a review,
  which only resolves the request once enough reviews meet the request's
  threshold rules (an "ineffectual review" leaves the request PENDING).
  This is exactly what `tsh request approve`/`tsh request deny` call --
  confirmed by reading tool/tsh/common/access_request.go's
  onRequestReview() in Teleport's source (the exact RequestID/Review
  shape here mirrors it).
- `SetAccessRequestState` is a direct, unconditional state set, bypassing
  the review/threshold system entirely -- more of an admin/raw-access
  tool than something a human reviewer would call.

Whether your identity is actually allowed to review a given request
depends on the *requested role's* `allow.review_requests` configuration,
not just generic access_request read/write permissions -- a different
authorization check than the one covered in the README's RBAC gotcha for
list/read.

Usage (routed through a Teleport Proxy, the default):
    python3 approve_access_request.py <request-id> --approve \\
        --author alice \\
        --reason "approved via gRPC example" \\
        --proxy <proxy-host>:443 --cluster-name <cluster> \\
        --key identity.key --cert identity.crt --cas identity.cas

Pair with create_access_request_example.py: run that first, copy the "id:"
it prints, then pass it here. Run with --help to see all connection flags
(including --direct, to connect to Auth's own port instead).
"""
import argparse

from teleport_grpc_client import add_connection_args, build_stub_from_args
from teleport.legacy.types import types_pb2


def submit_access_review(stub, request_id: str, approve: bool, author: str = "", reason: str = ""):
    state = types_pb2.RequestState.APPROVED if approve else types_pb2.RequestState.DENIED
    submission = types_pb2.AccessReviewSubmission(
        RequestID=request_id,
        Review=types_pb2.AccessReview(
            Author=author,
            ProposedState=state,
            Reason=reason,
        ),
    )
    return stub.SubmitAccessReview(submission)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_connection_args(parser)
    parser.add_argument("request_id", help="ID of the access request to review")
    decision = parser.add_mutually_exclusive_group()
    decision.add_argument("--approve", action="store_true", help="approve the request (default)")
    decision.add_argument("--deny", action="store_true", help="deny the request")
    parser.add_argument(
        "--author", default="", help="Teleport username of the review author (an audit/display field -- "
        "authorization is based on your mTLS identity, not this string)"
    )
    parser.add_argument("--reason", default="approved via gRPC example", help="review reason (default: %(default)s)")
    args = parser.parse_args()

    stub, close = build_stub_from_args(args)
    try:
        req = submit_access_review(
            stub, args.request_id, approve=not args.deny, author=args.author, reason=args.reason
        )
        state_name = types_pb2.RequestState.Name(req.Spec.State)
        if req.Spec.State == types_pb2.RequestState.PENDING:
            print(f"Review submitted, but request is still PENDING (threshold not yet met): {args.request_id}")
        else:
            print(f"{args.request_id}  state={state_name}")
    finally:
        close()


if __name__ == "__main__":
    main()
