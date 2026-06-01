import json
import base64
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _decode_jwt_claims(token: str) -> dict:
    payload = token.split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


def lambda_handler(event, context):
    logger.info(f"Interceptor input keys: {list(event.keys())}")

    mcp_data        = event.get('mcp', {})
    gateway_request = mcp_data.get('gatewayRequest', {})
    headers         = gateway_request.get('headers', {})
    body            = gateway_request.get('body', {})

    # Decode the Teleport JWT — already validated by the gateway, no re-verify needed
    teleport_user  = 'unknown'
    teleport_roles = ''
    auth_header = headers.get('Authorization') or headers.get('authorization', '')
    if auth_header.startswith('Bearer '):
        try:
            claims        = _decode_jwt_claims(auth_header[7:])
            teleport_user = claims.get('sub', 'unknown')
            roles         = claims.get('roles', [])
            teleport_roles = ','.join(roles) if isinstance(roles, list) else str(roles)
            logger.info(f"Teleport identity: sub={teleport_user} roles={teleport_roles}")
        except Exception as e:
            logger.warning(f"Failed to decode JWT: {e}")

    # Inject identity into tool arguments so the tool Lambda event receives them.
    # Only tools/call carries arguments; initialize and tools/list pass through unchanged.
    method = body.get('method', '')
    if method == 'tools/call':
        params = body.setdefault('params', {})
        args   = params.setdefault('arguments', {})
        args['_teleport_user']  = teleport_user
        args['_teleport_roles'] = teleport_roles
        logger.info(f"Injected identity into tools/call arguments for tool: {params.get('name')}")

    return {
        'interceptorOutputVersion': '1.0',
        'mcp': {
            'transformedGatewayRequest': {
                'headers': headers,
                'body': body,
            }
        }
    }