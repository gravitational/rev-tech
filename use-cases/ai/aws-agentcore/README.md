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

Teleport's `tsh mcp connect` proxy forwards the signed JWT to the gateway as a Bearer token,
so every tool invocation carries a verified, auditable caller identity.

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
Tool Lambda
  │  whoami_tool       → returns caller identity from JWT claims
  │  get_order_tool    → retrieve order data
  │  update_order_tool → update order data
```

### Tutorial Details

| | |
|:---|:---|
| **Tutorial type** | Interactive (Jupyter notebooks) |
| **AgentCore components** | AgentCore Gateway |
| **Identity provider** | Teleport (OIDC) |
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

## Prerequisites

- AWS credentials with permissions for Lambda, IAM, bedrock-agentcore
- A Teleport cluster (self-hosted or Teleport Cloud) with admin access
- `tsh` installed and logged in (`tsh login --proxy=<your-cluster>`)
- Python 3.9+

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

Run notebook **01**. It is idempotent — re-running a cell that already created a resource
will skip creation gracefully.

After notebook 01 completes and prints the gateway URL, complete the Teleport agent
setup below.

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
version: v8
metadata:
  description: Access to MCP servers
  name: mcp-user
spec:
  allow:
    app_labels:
      teleport.internal/app-sub-kind: mcp
    mcp:
      tools:
      - '*'
```

```bash
tctl create -f mcp-user-role.yaml
tctl users update <your-username> --set-roles=...,mcp-user
```

If you are using SSO integration you may need to update your `claims_to_roles` (OIDC) or `attrbutes_to_roles` to enable the user to have acccess to the mcp-user role.  See Teleport [docs] (https://goteleport.com/docs/zero-trust-access/sso/integrate-idp/oidc/)  for details.

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
| `teleport.yaml` | Teleport app service config pointing at the AgentCore Gateway |
| `test-mcp.sh` | Shell script to test the MCP endpoint directly via `tsh mcp connect` |
| `.env.example` | Template for AWS credential environment variables |
