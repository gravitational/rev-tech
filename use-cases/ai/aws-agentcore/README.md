# MCP-ify your AWS Lambda with Teleport + AgentCore Gateway
## Transform AWS Lambda functions into zero-trust MCP tools protected by Teleport identity

## Overview

Bedrock AgentCore Gateway turns existing AWS Lambda functions into fully-managed MCP servers
without requiring any infrastructure changes. This series extends that pattern with
**Teleport as the OIDC identity provider**, so the same zero-trust policies that control
infrastructure access also control AI tool access — verified, auditable, and policy-driven
at every hop.

AgentCore Gateway employs a dual authentication model:

- **Inbound Auth** — validates and authorizes users attempting to access gateway targets.
  Here that is a Teleport-issued JWT, validated against Teleport's OIDC discovery URL.
  Only users with the `mcp-user` Teleport role can reach the gateway at all.

- **Outbound Auth** — enables the gateway to securely connect to backend resources.
  Here that is an IAM role that grants the gateway permission to invoke the tool Lambdas.

Teleport's `tsh mcp connect` proxy forwards the signed JWT to the gateway as a Bearer token.
A REQUEST interceptor Lambda decodes that JWT and injects the caller's verified identity
(`_teleport_user`, `_teleport_roles`) into every tool call — so Lambda tools know *who*
called them without any authentication code of their own.

Notebook 04 closes the final gap: the Lambda still runs under its IAM execution role, so
CloudTrail shows the role — not the user. **IAM Identity Center Trusted Token Issuers (TTI)**
fix this. The interceptor exchanges the Teleport JWT for an Identity Center token, then
assumes a user-scoped IAM role with the user's email as the `RoleSessionName`. Every AWS API
call made with those credentials appears in CloudTrail as the user, not the agent.

### Architecture

```
Developer
  │  tsh login → tsh mcp connect agentcore-gateway
  ↓
Teleport Proxy  (issues JWT: sub, roles, aud)
  │  mcp+https://  Authorization: Bearer <teleport-jwt>
  ↓
AgentCore Gateway
  │  Validates JWT against Teleport OIDC discovery URL
  │  Enforces: roles CONTAINS "mcp-user"
  ↓
REQUEST Interceptor Lambda
  │  Decodes JWT → sub, roles   (no re-verify — gateway already did it)
  │  Calls Amazon Verified Permissions (Cedar policy)
  │  DENY  → MCP error returned, tool Lambda never invoked
  │  ALLOW → inject _teleport_user + _teleport_roles into tool arguments
  │
  │  [Notebook 04 — TTI] sso-oidc:CreateTokenWithIAM (exchanges Teleport JWT via IC TTI)
  │  [Notebook 04 — TTI] sts:AssumeRole (RoleSessionName = user email)
  ↓
Tool Lambda
  │  whoami_tool       → returns verified caller identity + user-scoped AWS ARN
  │  get_order_tool    → readable by mcp-user role (Cedar ALLOW)
  │  update_order_tool → requires order-admin role  (Cedar DENY for mcp-user)
  ↓
CloudTrail
     assumed-role/<role>/user@example.com  ← AWS calls attributed to the user, not the agent
```

### Tutorial Details

| | |
|:---|:---|
| **Tutorial type** | Interactive (Jupyter notebooks) |
| **AgentCore components** | AgentCore Gateway |
| **Identity provider** | Teleport (OIDC) |
| **Authorization** | Amazon Verified Permissions (Cedar policies) |
| **Gateway target** | AWS Lambda |
| **MCP transport** | `mcp+https` (Streamable HTTP) |
| **SDK** | boto3 / tsh CLI |

## Notebooks

### 01 — Gateway + Tool Lambda
`01-teleport-agentcore-identity-demo.ipynb`

Sets up the foundation:
- Deploys the tool Lambda (`whoami_tool`, `get_order_tool`, `update_order_tool`)
- Creates the AgentCore Gateway with Teleport OIDC JWT authorizer
- Registers the Lambda as an MCP target
- Smoke-tests via `tsh mcp connect`

### 02 — Interceptor: Identity Injection
`02-interceptor-identity-injection.ipynb`

Bridges the identity gap — AgentCore validates the JWT but doesn't forward it to Lambda:
- Deploys a REQUEST interceptor Lambda
- Interceptor decodes the Teleport JWT and injects `_teleport_user` + `_teleport_roles`
  into every `tools/call` invocation
- After this notebook, `whoami_tool` returns the real Teleport identity

### 03 — Cedar Policy Authorization
`03-cedar-avp-authorization.ipynb`

Adds policy enforcement via Amazon Verified Permissions:
- Creates an AVP policy store with Cedar policies mapping Teleport roles to tools
- `mcp-user` → `whoami_tool`, `get_order_tool`
- `order-admin` → `update_order_tool`  *(caller does not hold this role — expect DENY)*
- Deploys the AVP-aware interceptor (`lambda_interceptor_avp.py`)
- **Live policy change demo**: grants `mcp-user` access to `update_order_tool` by adding
  a Cedar policy in AVP — no Lambda redeployment, no gateway restart

### 04 — TTI User Identity (CloudTrail Attribution)
`04-tti-user-identity.ipynb`

Closes the final identity gap — Lambdas run under their IAM execution role, so CloudTrail
attributes calls to the role, not the user. This notebook fixes that with IAM Identity
Center Trusted Token Issuers:

**Phase 0** (setup, idempotent):
- Discovers the IC instance ARN and writes it to `.env`
- Creates a Trusted Token Issuer pointing at the Teleport cluster OIDC endpoint
- Creates a Customer Managed Application with a `jwt-bearer` grant
- Creates IC users from `DEMO_USER_EMAILS` and assigns them to the application

**Steps 1–7** (IAM wiring + Lambda deployment):
- Creates `agentcore-user-role` trusted by the interceptor Lambda's execution role
- Grants the interceptor `sso-oauth:CreateTokenWithIAM` + `sts:AssumeRole`
- Updates the Application Actor Policy to include the interceptor role
- Deploys updated interceptor and tool Lambda with TTI environment variables
- **Test**: `whoami_tool` now returns two ARNs — `lambda_execution_role` (static) and
  `aws_caller` (user-scoped session named after the Teleport user's email)
- **CloudTrail**: every tool invocation appears as `assumed-role/<role>/user@example.com`

The identity chain is unbroken end to end:

| Layer | Identity |
|:------|:---------|
| Teleport JWT `sub` | `user@example.com` |
| IC token exchange | IC validates user via TTI |
| STS session name | `user@example.com` (set by interceptor via `RoleSessionName`) |
| `aws_caller.Arn` | `arn:aws:sts::<account>:assumed-role/<role>/user@example.com` |
| CloudTrail actor | `assumed-role/<role>/user@example.com` |

## Prerequisites

- AWS credentials with permissions for Lambda, IAM, bedrock-agentcore, verifiedpermissions
- A Teleport cluster (self-hosted or Teleport Cloud) with admin access
- `tsh` installed and logged in (`tsh login --proxy=<your-cluster>`)
- Python 3.9+
- *(Notebook 04 only)* IAM Identity Center enabled in your AWS account with
  Identity-Enhanced Sessions turned on: **IAM Identity Center → Settings → Enable identity-enhanced sessions**

## Setup

### 1. Python environment

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# edit .env with your AWS credentials
```

### 2. Run the notebooks

Run in order: **01 → 02 → 03 → 04**. Each notebook is self-contained and idempotent —
re-running a cell that already created a resource will skip creation gracefully.

After notebook 01 completes and prints the gateway URL, complete the Teleport agent
setup below before proceeding to notebook 02.

### 3. Configure the Teleport app agent

The Teleport app service acts as the MCP proxy. It authenticates users via `tsh`,
issues a signed JWT with the user's identity and roles, and forwards requests to the
AgentCore Gateway with that JWT as the `Authorization: Bearer` header.

**3a. Create a join token**

```bash
tctl tokens add --type=app --ttl=1h
```

Copy the token value into `teleport.yaml` under `auth_token`.

**3b. Update `teleport.yaml`**

Edit `teleport.yaml` and set:

```yaml
teleport:
  proxy_server: <your-cluster>:443   # e.g. example.teleport.sh:443
  auth_token: <token-from-step-3a>
  data_dir: /path/to/data            # writable directory for agent state

app_service:
  enabled: true
  apps:
    - name: agentcore-gateway
      uri: "mcp+https://<gateway-url>/mcp"   # printed by notebook 01
      rewrite:
        headers:
          - "Authorization: Bearer {{internal.id_token}}"
```

The `{{internal.id_token}}` rewrite tells Teleport to attach a signed JWT to every
outbound request. AgentCore Gateway validates this JWT against Teleport's OIDC
discovery URL (`https://<your-cluster>/.well-known/openid-configuration`).

**3c. Start the agent**

```bash
teleport start --config=teleport.yaml
```

The agent registers the `agentcore-gateway` app in your Teleport cluster. Verify it
appeared with:

```bash
tsh apps ls
```

**3d. Create the `mcp-user` Teleport role**

AgentCore Gateway requires the inbound JWT to contain `roles` CONTAINS `"mcp-user"`.
Create the role if it doesn't exist:

```yaml
# mcp-user-role.yaml
kind: role
version: v7
metadata:
  name: mcp-user
spec:
  allow:
    app_labels:
      '*': '*'
```

```bash
tctl create -f mcp-user-role.yaml
tctl users update <your-username> --set-roles=...,mcp-user
```

### 4. Connect and test

```bash
tsh app login agentcore-gateway
tsh mcp connect agentcore-gateway
```

Or use the test script:

```bash
bash test-mcp.sh
```

## Files

| File | Purpose |
|:-----|:--------|
| `lambda_tool.py` | Tool Lambda handler (whoami, get_order, update_order) |
| `lambda_interceptor.py` | REQUEST interceptor — identity injection only |
| `lambda_interceptor_avp.py` | REQUEST interceptor — identity injection + Cedar/AVP enforcement + TTI exchange |
| `teleport.yaml` | Teleport app service config pointing at the AgentCore Gateway |
| `test-mcp.sh` | Shell script to test the MCP endpoint directly via `tsh mcp connect` |
| `DEMO-PLAN.md` | Full architecture doc including Scenario 2 (RFC 8693 / Keycloak OBO) |
| `.env.example` | Template for AWS credential environment variables |

## References

- RFC 8693 OAuth 2.0 Token Exchange: https://datatracker.ietf.org/doc/html/rfc8693
- AWS AgentCore OBO docs: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/on-behalf-of-token-exchange.html
- Teleport AgentCore Gateway integration: https://goteleport.com/docs/enroll-resources/mcp-access/integration-guides/aws-bedrock-gateway/
- AWS IAM Identity Center TTI setup: https://docs.aws.amazon.com/singlesignon/latest/userguide/setuptrustedtokenissuer.html
- Teleport Identity Center integration: https://goteleport.com/docs/identity-governance/integrations/aws-iam-identity-center/