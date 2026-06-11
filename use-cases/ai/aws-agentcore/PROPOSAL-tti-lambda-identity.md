# TTI-Based AWS User Identity — Design Notes

## Problem

Notebooks 01–03 prove Teleport identity at the application layer — `whoami_tool`
returns the Teleport `sub` claim injected by the interceptor. But the tool Lambda
still executes under its IAM execution role. CloudTrail shows the role, not the user.
AWS services called by the tool Lambda run with the role's permissions, not the user's.

The goal: every AWS API call made through the agent is audited against the Teleport
user, not the execution role.

---

## Architecture

The interceptor performs a two-step identity flow on every tool call:

1. **IC TTI validation** — exchange the Teleport `id_token` for an Identity Center
   token via `sso-oidc:CreateTokenWithIAM`. This proves the caller exists in IC and
   is assigned to the Application. Fails closed if the user isn't found.

2. **`sts:AssumeRole`** — assume the user-scoped role with the user's email as
   `RoleSessionName`. The resulting session ARN contains the email; CloudTrail
   attributes all API calls from those credentials to the user.

```
Teleport id_token
  → Interceptor: sso-oidc:CreateTokenWithIAM  → IC validates user identity
  → Interceptor: sts:AssumeRole (RoleSessionName=user@email) → temp credentials
  → Tool Lambda: sts:GetCallerIdentity → ARN contains user email
  → CloudTrail:  assumed-role/<role>/user@example.com
```

### Key Architectural Decision: Why Not `AssumeRoleWithWebIdentity`?

The natural design would be to federate the IC token directly into STS via
`AssumeRoleWithWebIdentity`. This doesn't work: IC's `CreateTokenWithIAM` uses
**internal signing keys** that are not published via OIDC discovery
(`/.well-known/openid-configuration` returns 404). STS cannot verify the token
signature, so `AssumeRoleWithWebIdentity` always returns
`InvalidIdentityToken: Couldn't retrieve verification key from your identity provider`.

The IC TTI exchange is kept as the **identity validation gate** — it proves the user
exists in IC and is authorized — but `sts:AssumeRole` is used directly for credential
generation, with the user email as the session name to preserve CloudTrail attribution.

---

## Risks and Considerations

| Risk | Mitigation |
|---|---|
| Credential injection via event args is cleartext in Lambda logs if log level is DEBUG | Log level set to INFO; event args not logged |
| STS temp credentials expire (default 1hr) | Per-invocation credentials — each interceptor call gets fresh creds; no caching needed |
| User not in Identity Center | TTI exchange fails closed; interceptor logs warning, tool runs without user creds |
| User in IC but not assigned to the Application | `CreateTokenWithIAM` returns `UnauthorizedClient`; same graceful fallback |
| `RoleSessionName` capped at 64 chars | Email truncated to 64 chars in the interceptor |

---

## Implementation

See `04-tti-user-identity.ipynb` for the full automated setup and `lambda_interceptor_avp.py`
for the interceptor code.
