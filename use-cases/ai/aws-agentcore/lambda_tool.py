import json

# Tool Lambda — identity-aware handler for AgentCore Gateway demo.
#
# X-Teleport-User and X-Teleport-Roles are injected by the REQUEST interceptor
# after it decodes the validated Teleport JWT. Before the interceptor is wired in,
# these headers are absent and the caller fields return "unknown".

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
        return {
            'statusCode': 200,
            'body': json.dumps({
                'caller': teleport_user,
                'roles':  teleport_roles.split(',') if teleport_roles else [],
                'gateway_id': custom.get('bedrockAgentCoreGatewayId'),
                'session_id': custom.get('bedrockAgentCoreSessionId', ''),
            })
        }

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