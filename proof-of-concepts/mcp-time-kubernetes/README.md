# Purpose
Basic example of teleport running in a container on kubernetes that can run uvx to execute MCP tools for using stdio instead of sse/http. 
In this case, the MCP tool is able to provide the current time to the AI model.

This is intended for anyone looking to run Teleport's MCP integration in a container on Kubernetes.

## Prerequisites
You should have a Teleport Cluster >=18.1.0 running in Kubernetes. If the cluster is outside of kubernetes, you may need to change the join method. You should also have an AI client capable of using MCP. I tested this with LM-Studio using Qwen3. Claude and Cursor should work fine as well. 

## Configure
There's a few placeholder values:

- `deployment.yaml` you will need to change the namespace and the image name to match your mcp tool namespace and your image created with the Dockerfile
- `configmap.yaml` you will need to change the namespace and your proxy_server address, as well as the default time zone for the time mcp application (optional)
- `Dockerfile` you will need to change the teleport version to match your cluster. The example has ent-v18.2.4. Optionally you can also add any certificates before update-ca-certificates if needed to connect to your teleport cluster.
- `sa.yaml` you will need to change the namespace, or use the default service account in token.yaml
- `token.yaml` you will need to change the service account namespace to match your mcp tool namespace, and optionally change the sa to the default service account for the namespace if specified in deployment.yaml (you won't need sa.yaml in this case)

## Deploy
To deploy the container, follow these steps:

- create token.yaml with `tctl create -f token.yaml` 
- build/push the docker image with `docker build -t your-repo/image:tag .` 
- create the service account, configmap, and deployment on kubernetes with 

```bash
kubectl create -f sa.yaml
kubectl create -f configmap.yaml
kubectl create -f deployment.yaml
```

## Run
To use the tool, get the MCP configuration with `tsh mcp config --labels env=container`, open up anything with MCP tool access (I'm using LM Studio with qwen3-14b), add the configuration to mcp.json, and enable the tool.

## Example output
I asked `what time is it?` and got the response:

```md
The current time in Denver (America/Denver) is 2:40 PM on Thursday, October 16th 2025. Daylight Saving Time is currently active in this timezone. Let me know if you need the time in another location!
```
I can see in the container's logs that is is actively sending/receiving information from my local tool with my teleport user.

This is just an example, but it shows you can run teleport and the MCP tool in the same container, use teleport to access the tool remotely, and auto-join the teleport-cluster with a service account.

## Troubleshooting
Teleport is not able to connect to my cluster!

- Verify you have changed the proxy address in `configmap.yaml`
- Verify the token name matches from `token.yaml` with `configmap.yaml` 
- Verify you have created the service account (`sa.yaml`), the service account name is listed properly in `deployment.yaml`, and service_account is in the format namespace:serviceaccountname in `token.yaml`

I don't see any MCP tools listed when running `tsh mcp ls`!

- Verify teleport is running and connected in the container, and app_service is enabled under `configmap.yaml` 

I added the MCP tool to lm-studio/claude/cursor, but it's not working!

- Verify the model you are using supports MCP tools. In LM-Studio, you can check by looking for the hammer icon next to the model name. 
- Check the logs in the container to see if any errors occur when running the time tool
- Check the audit log in Teleport for any errors in the MCP request

## Support
This example was created by Rhett Sandal. Please reach out for any help in Slack or to my email: rhett.sandal@goteleport.com 