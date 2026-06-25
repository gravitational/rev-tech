import json
import base64
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

avp = boto3.client('verifiedpermissions')
POLICY_STORE_ID     = os.environ.get('AVP_POLICY_STORE_ID', '')
TTI_APPLICATION_ARN = os.environ.get('TTI_APPLICATION_ARN', '')
USER_ROLE_ARN       = os.environ.get('USER_ROLE_ARN', '')
IC_REGION           = os.environ.get('IDENTITY_CENTER_REGION', 'us-east-1')


def _exchange_token_for_credentials(id_token: str, user_email: str) -> dict | None:
    """
    Two-step identity flow:
      1. Teleport id_token → IC TTI validation (proves user exists in Identity Center)
      2. sts:AssumeRole with user email as RoleSessionName → CloudTrail attribution
    Returns STS Credentials dict or None when TTI is not configured or validation fails.
    """
    if not TTI_APPLICATION_ARN or not USER_ROLE_ARN:
        return None

    # Step 1: validate user through IC TTI — fails closed if user isn't in IC
    try:
        sso_oidc = boto3.client('sso-oidc', region_name=IC_REGION)
        sso_oidc.create_token_with_iam(
            clientId=TTI_APPLICATION_ARN,
            grantType='urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion=id_token,
        )
        logger.info(f'IC TTI validated {user_email}')
    except Exception as e:
        logger.error(f'TTI validation failed: {e}')
        return None

    # Step 2: assume user-scoped role; session name = email → CloudTrail shows user
    try:
        sts  = boto3.client('sts')
        resp = sts.assume_role(
            RoleArn=USER_ROLE_ARN,
            RoleSessionName=user_email[:64],
        )
        return resp['Credentials']
    except Exception as e:
        logger.error(f'AssumeRole failed: {e}')
        return None


def _decode_jwt_claims(token: str) -> dict:
    payload = token.split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


def _tool_name(full_name: str) -> str:
    """Strip target prefix: 'TeleportDemo___get_order_tool' → 'get_order_tool'"""
    delimiter = '___'
    if delimiter in full_name:
        return full_name[full_name.index(delimiter) + len(delimiter):]
    return full_name


def _avp_deny_response(request_id, tool_name: str, reasons: list) -> dict:
    reason_str = '; '.join(reasons) if reasons else 'policy deny'
    return {
        'interceptorOutputVersion': '1.0',
        'mcp': {
            'transformedGatewayResponse': {
                'statusCode': 403,
                'body': {
                    'jsonrpc': '2.0',
                    'id': request_id,
                    'error': {
                        'code': -32001,
                        'message': f'Access denied: {reason_str}',
                        'data': {'tool': tool_name}
                    }
                }
            }
        }
    }


def lambda_handler(event, context):
    mcp_data        = event.get('mcp', {})
    gateway_request = mcp_data.get('gatewayRequest', {})
    headers         = gateway_request.get('headers', {})
    body            = gateway_request.get('body', {})

    # --- Decode Teleport JWT (already validated by the gateway) ---
    teleport_user  = 'unknown'
    teleport_roles = []
    auth_header = headers.get('Authorization') or headers.get('authorization', '')
    if auth_header.startswith('Bearer '):
        try:
            claims = _decode_jwt_claims(auth_header[7:])
            teleport_user  = claims.get('sub', 'unknown')
            roles          = claims.get('roles', [])
            teleport_roles = roles if isinstance(roles, list) else [str(roles)]
            logger.info(f'Identity: sub={teleport_user} roles={teleport_roles}')
            logger.info(f'JWT aud={claims.get("aud")} iss={claims.get("iss")}')
        except Exception as e:
            logger.warning(f'Failed to decode JWT: {e}')

    method = body.get('method', '')

    # --- AVP authorization for tool calls ---
    if method == 'tools/call' and POLICY_STORE_ID:
        full_tool_name = body.get('params', {}).get('name', '')
        tool           = _tool_name(full_tool_name)
        request_id     = body.get('id', 0)

        # Build entity list: user is a member of each Teleport role
        entities = [{
            'identifier': {'entityType': 'TeleportUser', 'entityId': teleport_user},
            'attributes': {},
            'parents': [
                {'entityType': 'TeleportRole', 'entityId': role}
                for role in teleport_roles
            ]
        }]

        try:
            resp = avp.is_authorized(
                policyStoreId=POLICY_STORE_ID,
                principal={'entityType': 'TeleportUser', 'entityId': teleport_user},
                action={'actionType':   'Action',        'actionId':   'invoke_tool'},
                resource={'entityType': 'Tool',          'entityId':   tool},
                entities={'entityList': entities},
            )
            decision = resp['decision']
            reasons  = [r.get('policyId', '') for r in resp.get('determiningPolicies', [])]
            logger.info(f'AVP {decision}: user={teleport_user} tool={tool} policies={reasons}')

            if decision == 'DENY':
                return _avp_deny_response(request_id, tool, [f'no policy permits {tool}'])

        except Exception as e:
            logger.error(f'AVP call failed: {e}')
            # Fail closed — deny if we can't reach AVP
            return _avp_deny_response(request_id, tool, ['authorization service unavailable'])

    # --- Inject identity and optional user-scoped AWS credentials ---
    if method == 'tools/call':
        args = body.setdefault('params', {}).setdefault('arguments', {})
        args['_teleport_user']  = teleport_user
        args['_teleport_roles'] = ','.join(teleport_roles)

        raw_token = auth_header[7:] if auth_header.startswith('Bearer ') else ''
        creds = _exchange_token_for_credentials(raw_token, teleport_user)
        if creds:
            args['_aws_access_key']    = creds['AccessKeyId']
            args['_aws_secret_key']    = creds['SecretAccessKey']
            args['_aws_session_token'] = creds['SessionToken']
            logger.info(f'Injected user-scoped credentials for {teleport_user}')
        elif TTI_APPLICATION_ARN:
            logger.warning(f'TTI exchange failed for {teleport_user} — continuing without user credentials')

    return {
        'interceptorOutputVersion': '1.0',
        'mcp': {
            'transformedGatewayRequest': {
                'headers': headers,
                'body':    body,
            }
        }
    }
