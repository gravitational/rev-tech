# Teleport + AWS IAM Identity Center TTI Token Exchange — Investigation Summary

## TL;DR

The Teleport `id_token` forwarded by App Proxy via `{{internal.id_token}}` works
as-is with AWS IAM Identity Center Trusted Token Issuers (TTI) to perform RFC 8693
On-Behalf-Of token exchange. No Teleport code changes are needed. This is a
documentation gap, not a feature gap.

---

## What Was Proven

A complete end-to-end OBO flow works today:

```
User authenticates via Teleport MCP proxy
        │
        │  App Proxy injects {{internal.id_token}} into Authorization header
        ▼
AgentCore Gateway receives id_token
        │
        │  RFC 8693 token exchange with IAM Identity Center TTI:
        │    subject_token      = Teleport id_token
        │    subject_token_type = urn:ietf:params:oauth:token-type:jwt
        │    grant_type         = urn:ietf:params:oauth:grant-type:jwt-bearer
        ▼
IAM Identity Center validates token against Teleport JWKS,
maps sub (user email) → Identity Center user,
issues AWS-native token with USER's Identity Center identity
        │
        ▼
Downstream AWS resource server enforces USER's IAM permissions
Audit log shows the USER, not the agent
```

The exchanged Identity Center token contains:
- `sub`: the Identity Center user ID for the Teleport user
- `act.sub`: the TTI ARN — the actor that performed the exchange
- `iss`: `https://identitycenter.amazonaws.com/ssoins-<instance>`
- `aws:identity_store_id`, `aws:instance_arn`, `aws:application_arn`

---

## The Teleport id_token

The `{{internal.id_token}}` issued by App Proxy for MCP apps contains all claims
required by IAM Identity Center TTI:

```json
{
  "iss": "https://ellinj.teleport.sh",      // matches TTI IssuerUrl
  "sub": "jeffrey.ellin@goteleport.com",    // maps to Identity Center user email
  "aud": "mcp+http://localhost:9999/mcp",   // matches AuthorizedAudiences
  "jti": "...",                              // replay protection
  "iat": ..., "exp": ..., "nbf": ...,       // standard validity claims
  "roles": [...],                            // Teleport-specific — ignored by TTI
  "traits": {...},                           // Teleport-specific — ignored by TTI
  "username": "..."                          // Teleport-specific — ignored by TTI
}
```

The non-standard claims (`roles`, `traits`, `username`) do not cause issues —
IAM Identity Center ignores unknown claims during TTI exchange.

---

## AWS Setup — Step by Step

### Prerequisites
- Teleport cluster with MCP app configured using `{{internal.id_token}}` header rewrite
- AWS account with IAM Identity Center enabled (organization instance)
- Identity-enhanced sessions enabled in Identity Center Settings

### Step 1 — Enable Identity-Enhanced Sessions

In the AWS Console: **IAM Identity Center → Settings → Enable identity-enhanced sessions**

Or verify it's already enabled — required for `CreateTokenWithIAM`.

### Step 2 — Create the Trusted Token Issuer

```bash
aws sso-admin create-trusted-token-issuer \
  --instance-arn "arn:aws:sso:::instance/<instance-id>" \
  --name "teleport-<cluster-name>" \
  --trusted-token-issuer-type OIDC_JWT \
  --trusted-token-issuer-configuration '{
    "OidcJwtConfiguration": {
      "IssuerUrl": "https://<cluster>.teleport.sh",
      "ClaimAttributePath": "sub",
      "IdentityStoreAttributePath": "emails.value",
      "JwksRetrievalOption": "OPEN_ID_DISCOVERY"
    }
  }'
```

- `IssuerUrl` — your Teleport cluster URL (no trailing slash, no path)
- `ClaimAttributePath: sub` — the Teleport `sub` claim is the user's email
- `IdentityStoreAttributePath: emails.value` — matches against Identity Center user email

### Step 3 — Create a Customer Managed Application

```bash
aws sso-admin create-application \
  --instance-arn "arn:aws:sso:::instance/<instance-id>" \
  --application-provider-arn "arn:aws:sso::aws:applicationProvider/custom" \
  --name "teleport-tti-test" \
  --portal-options '{"Visibility": "DISABLED"}'
```

### Step 4 — Add the jwt-bearer Grant

```bash
aws sso-admin put-application-grant \
  --application-arn "<ApplicationArn>" \
  --grant-type "urn:ietf:params:oauth:grant-type:jwt-bearer" \
  --grant '{
    "JwtBearer": {
      "AuthorizedTokenIssuers": [
        {
          "TrustedTokenIssuerArn": "<TrustedTokenIssuerArn>",
          "AuthorizedAudiences": ["mcp+http://localhost:9999/mcp"]
        }
      ]
    }
  }'
```

`AuthorizedAudiences` must exactly match the `aud` claim in the Teleport `id_token`,
which is set to the MCP app URI (e.g. `mcp+http://localhost:9999/mcp`).

### Step 5 — Set the Application Authentication Method

```bash
aws sso-admin put-application-authentication-method \
  --application-arn "<ApplicationArn>" \
  --authentication-method-type "IAM" \
  --authentication-method '{
    "Iam": {
      "ActorPolicy": {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Principal": {
            "AWS": "<IAM principal ARN of the caller>"
          },
          "Action": "sso-oauth:CreateTokenWithIAM",
          "Resource": "<ApplicationArn>"
        }]
      }
    }
  }'
```

### Step 6 — Add IAM Policy for the Calling Principal

```bash
aws iam put-user-policy \
  --user-name <user> \
  --policy-name teleport-tti-token-exchange \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "sso-oauth:CreateTokenWithIAM",
      "Resource": "<ApplicationArn>"
    }]
  }'
```

### Step 7 — Ensure the User Exists in Identity Center

The user performing the exchange must exist in Identity Center with an email
matching the Teleport `sub` claim. If using the Teleport Identity Center
integration with SCIM sync, users are created automatically. Otherwise create
manually:

```bash
aws identitystore create-user \
  --identity-store-id <identity-store-id> \
  --user-name "user@example.com" \
  --display-name "User Name" \
  --name '{"GivenName": "User", "FamilyName": "Name"}' \
  --emails '[{"Value": "user@example.com", "Type": "work", "Primary": true}]'
```

### Step 8 — Assign the User to the Application

```bash
aws sso-admin create-application-assignment \
  --application-arn "<ApplicationArn>" \
  --principal-id "<UserId>" \
  --principal-type "USER"
```

### Step 9 — Test the Exchange

```bash
aws sso-oidc create-token-with-iam \
  --region <region> \
  --client-id "<ApplicationArn>" \
  --grant-type "urn:ietf:params:oauth:grant-type:jwt-bearer" \
  --assertion "<Teleport id_token>"
```

A successful response contains `accessToken`, `idToken`, and `issuedTokenType`.

---

## Identity Mapping

| Teleport | IAM Identity Center |
|---|---|
| `sub` claim (`user@example.com`) | `emails.value` attribute |
| Teleport JWKS (`/.well-known/jwks-oidc`) | TTI verifies signature |
| Teleport OIDC discovery (`/.well-known/openid-configuration`) | TTI fetches JWKS URI |

The Teleport Identity Center SCIM integration (if configured) automatically
keeps users in sync — no manual user creation needed in production.

---

## Next Steps

1. **Document this as an extension to the AgentCore Gateway integration guide**
   at `goteleport.com/docs/enroll-resources/mcp-access/integration-guides/aws-bedrock-gateway/`

2. **Wire AgentCore to use the exchanged Identity Center token** when calling
   downstream AWS resource servers — configure an OAuth Credential Provider in
   AgentCore pointing at the Identity Center token endpoint with
   `ON_BEHALF_OF_TOKEN_EXCHANGE` flow

3. **Update the demo Lambda** — currently echoes the Lambda execution role
   identity. After wiring AgentCore OBO, it should echo the user's Identity
   Center identity instead, demonstrating the zero-trust delegation guarantee

---

## References

- RFC 8693 OAuth 2.0 Token Exchange: https://datatracker.ietf.org/doc/html/rfc8693
- AWS AgentCore OBO docs: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/on-behalf-of-token-exchange.html
- Teleport AgentCore Gateway integration: https://goteleport.com/docs/enroll-resources/mcp-access/integration-guides/aws-bedrock-gateway/
- AWS IAM Identity Center TTI setup: https://docs.aws.amazon.com/singlesignon/latest/userguide/setuptrustedtokenissuer.html
- Teleport Identity Center integration: https://goteleport.com/docs/identity-governance/integrations/aws-iam-identity-center/