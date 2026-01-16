# MongoDB Self-Hosted (Teleport)

This example provisions a self-hosted MongoDB database on EC2, sets up TLS, and uses the Teleport Database Service to register the database dynamically.

It mirrors the official [Teleport self-hosted MongoDB guide](https://goteleport.com/docs/enroll-resources/database-access/enroll-self-hosted-databases/mongodb-self-hosted/) and is modularized for reuse.

---

## What It Deploys

- 1 EC2 instance running MongoDB Community Edition 8.0 on Amazon Linux 2023
- A custom CA and server TLS certificate for encrypted MongoDB access
- Teleport agent with `db_service` and `ssh_service`
- Teleport dynamic discovery enabled via label matching: `tier = dev`

---

## Usage

0. Export variables related to your Teleport cluster (or fill these in when prompted).

```bash
export TF_VAR_user="dlg@example.com"
export TF_VAR_proxy_address="demo.example.com"
export TF_VAR_teleport_version="18.1.6"
export TF_VAR_region="us-east-2"
```

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
tsh db ls 
tsh db connect --db-user=reader --db-name dev mongodb-dev
```

5. Tear down:
```bash
terraform destroy
```

---

## Notes
- Teleport connects to MongoDB using mutual TLS
- Users `writer` and `reader` are created with Teleport cert CN mapping
- `mongodb-dev` is registered with the `teleport_database` resource
- Customize with your own CA or plug into SSM for secrets