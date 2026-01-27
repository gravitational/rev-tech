# HTTPBin App Access with Teleport

This example provisions a small HTTPBin application on EC2 and registers it with Teleport App Access for quick demo workflows.

It mirrors the official [Protect a Web Application with Teleport](https://goteleport.com/docs/enroll-resources/application-access/getting-started/) guide and is modularized for reuse.

---

## What It Deploys

- 1 EC2 instance running HTTPBin
- Teleport agent with `app_service` and `ssh_service`
- Teleport app registration with `env` + `team` labels (e.g., `env = dev`, `team = platform`)

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
export TF_VAR_team="platform"
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
tsh apps ls env=dev,team=platform
tsh apps login httpbin-dev
```

5. Tear down:

```bash
terraform destroy
```

---

## Notes
- App public address is registered as `httpbin-<env>.<proxy_address>`
- Customize labels to match your RBAC scheme
