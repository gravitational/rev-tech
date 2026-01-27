# Grafana JWT App Access with Teleport

This example provisions a self-hosted Grafana container on EC2 and uses the Teleport App Access Service to register the application dynamically.

It mirrors the official [Protect a Web Application with Teleport](https://goteleport.com/docs/enroll-resources/application-access/getting-started/) and [Use JWT Tokens With Application Access](https://goteleport.com/docs/enroll-resources/application-access/jwt/introduction/) guides and is modularized for reuse.

---

## What It Deploys

- 1 EC2 instance running Grafana on Docker
- Teleport agent with `app_service` and `ssh_service`
- Teleport app registered via dynamic resource registration

---

## Usage

1. Authenticate to your Teleport cluster:

```bash
tsh login --proxy=teleport.example.com --auth=example
eval $(tctl terraform env)
```

2. Set variables (preferred) or use a tfvars file:

```bash
export TF_VAR_user="engineer@example.com"
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_teleport_version="18.6.4"
export TF_VAR_region="us-east-2"
export TF_VAR_env="dev"
```

Or:

```bash
cp terraform.tfvars.example terraform.tfvars
```

3. Deploy:
```bash
terraform init
terraform apply
```

4. Access:
```bash
tsh apps ls --labels=tier=dev
tsh apps login grafana-dev
```

5. Tear down:
```bash
terraform destroy
```

---

## Notes
- Grafana is exposed at `grafana-<env>.<proxy_address>` via Teleport App Access
