import json
import boto3


def _user_session(event: dict):
    """Build a boto3 session from interceptor-injected user credentials, or None."""
    key    = event.get('_aws_access_key')
    secret = event.get('_aws_secret_key')
    token  = event.get('_aws_session_token')
    if key and secret and token:
        return boto3.Session(
            aws_access_key_id=key,
            aws_secret_access_key=secret,
            aws_session_token=token,
        )
    return None


def lambda_handler(event, context):
    custom = context.client_context.custom
    tool_name = custom.get('bedrockAgentCoreToolName', '')

    delimiter = "___"
    if delimiter in tool_name:
        tool_name = tool_name[tool_name.index(delimiter) + len(delimiter):]

    # Identity injected by the interceptor lambda
    teleport_user  = event.get('_teleport_user', 'unknown (interceptor not yet configured)')
    teleport_roles = event.get('_teleport_roles', '')

    if tool_name == 'whoami_tool':
        result = {
            'teleport_caller':     teleport_user,
            'roles':               teleport_roles.split(',') if teleport_roles else [],
            'gateway_id':          custom.get('bedrockAgentCoreGatewayId'),
            'session_id':          custom.get('bedrockAgentCoreSessionId', ''),
            'lambda_execution_role': boto3.client('sts').get_caller_identity()['Arn'],
        }

        session = _user_session(event)
        if session:
            try:
                identity = session.client('sts').get_caller_identity()
                result['aws_caller'] = {
                    'UserId':  identity['UserId'],
                    'Account': identity['Account'],
                    'Arn':     identity['Arn'],
                }
            except Exception as e:
                result['aws_caller'] = f'credential error: {e}'
        else:
            result['aws_caller'] = 'no user credentials injected'

        return {'statusCode': 200, 'body': json.dumps(result)}

    elif tool_name == 'get_order_tool':
        order_id = event.get('orderId', 'unknown')
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'status':  'shipped',
                'caller':  teleport_user,
            })
        }

    elif tool_name == 'update_order_tool':
        order_id = event.get('orderId', 'unknown')
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'updated': True,
                'caller':  teleport_user,
            })
        }

    else:
        return {'statusCode': 400, 'body': f'Unknown tool: {tool_name}'}