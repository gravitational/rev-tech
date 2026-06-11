# Runbook: TTI-Based AWS User Identity in Lambda

Run `04-tti-user-identity.ipynb` — it handles all setup, deployment, and verification.

For design context and the reason `AssumeRoleWithWebIdentity` is not used, see
`PROPOSAL-tti-lambda-identity.md`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|:--------|:-------------|:----|
| `TTI validation failed: AccessDenied` in logs | Interceptor role missing `sso-oauth:CreateTokenWithIAM` | Re-run notebook Step 4 |
| `TTI validation failed: UnauthorizedClient` | Interceptor role not in Application Actor Policy | Re-run notebook Step 5 |
| `TTI validation failed: InvalidGrantException: Audience not allowed` | `AuthorizedAudiences` doesn't match the JWT `aud` claim | Re-run Phase 0 bootstrap cell — it resets the grant with the correct `mcp+<url>/mcp` audience |
| `AssumeRole failed: AccessDenied` | User role trust policy doesn't list the interceptor role, or `sts:AssumeRole` missing from interceptor policy | Re-run Steps 3 and 4 (`update_assume_role_policy` runs automatically on re-run) |
| `aws_caller: "no user credentials injected"` | Lambda not redeployed, or TTI env vars missing | Re-run Step 6; verify `TTI_APPLICATION_ARN` and `USER_ROLE_ARN` are set on the interceptor Lambda |
| `whoami_tool` returns 403 | AVP policy denies the user | Verify user's Teleport roles match a Cedar ALLOW policy in AVP |
| `_error: Teleport connection error` | Teleport session expired or MCP connection dropped | Run `tsh mcp login agentcore-gateway` and retry |
