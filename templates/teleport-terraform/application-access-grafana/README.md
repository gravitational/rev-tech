# Grafana JWT App Access with Teleport

This example provisions a self-hosted Grafana container on EC2 and uses the Teleport App Access Service to register the application dynamically.

It mirrors the official [Protect a Web Application with Teleport](https://goteleport.com/docs/enroll-resources/application-access/getting-started/) and [Use JWT Tokens With Application Access](https://goteleport.com/docs/enroll-resources/application-access/jwt/introduction/) guides and is modularized for reuse.

---

## What It Deploys

- 1 EC2 instance running Grafana on Docker
- Teleport agent with `app_service` and `ssh_service`
- Teleport dynamic discovery enabled via label matching: `tier : dev`

---

## Usage

1. Authenticate to your Teleport cluster:

```bash
tsh login --proxy=teleport.example.com --auth=example
eval $(tctl terraform env)
```

2. Customize the variables:
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
TBD
```

5. Tear down:
```bash
terraform destroy
```

---

## Notes
-