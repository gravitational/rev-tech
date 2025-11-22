# AWS Scalable App Proxy Deployment

> [!CAUTION]
> Please note that this repository was developed for testing environments and should not be used as is in your production environment. It is intended to serve as a reference or example. Use at your own risk; no support or warranty provided.

A proof of concept deployment of AWS Console and CLI Access proxy via multiple Teleport App Proxies. 

This primarily focuses on the ability to use IAM invite tokens for authenticating joining Teleport Agents with `App` role to enable use of Auto Scaling Groups to manage agent scaling.

## Requirements

- Publicly accessible Teleport tenant (Cloud or Self-hosted)
- Terraform
- AWS account

### Required Permissions

- Teleport cluster Join Token creation
- Teleport User Roles/Auth Connector modification
- AWS resource provisioning

## Setup

> [!WARNING]
> Port `22` on the Security Group will be open. This can be changed in the [terraform.tfvars](terraform.tfvars) should you require.

### Configuration

- (**Optionally**) Update the [main.tf](main.tf) to include a `backend` option to store state remotely.
- Update [terraform.tfvars](terraform.tfvars)
  - `proxy`: Set the field to your Teleport cluster domain (i.e: `example.teleport.sh`)
  - `tags`: Set any necessary tags that should be deployed with resource created by this module.

### Deployment

#### Infrastructure provisioning

Create the required resources for AWS Console and CLI Access 
```shell
# Initialise Terraform working directory
terraform init

# Create a infrastructure creation plan and approve
terraform apply
```

#### Teleport user update

- Update the user's User Roles to include the `teleport-demo-aws-proxy` role. If you're using an external authentication, update the connector configuration instead. Refer to the [Step 2/4. Configure Teleport IAM role mapping](https://goteleport.com/docs/enroll-resources/application-access/cloud-apis/aws-console/#step-24-configure-teleport-iam-role-mapping) for more information.
- Logout/Login to propagate the access change above.

## Testing

Once the deployment completed, you should have a new application called **awsconsole** along side two new EC2 instances. Deployment allows the EC2 SSH proxy to illustrate being able to join multiple resource using the IAM join method.

To test the AWS Console proxying:
- Connect to the both EC2 instances and follow the Teleport logs
  - `sudo journalctl -u teleport.service -f`
- Launch the AWS Console from the Teleport UI and observe the logs showing proxy traffic been load balanced on both instances.
- Downscale the ASG capacity to single instance for testing Teleport's app proxy traffic handling in a scenario where an agent dropping out of the cluster. 