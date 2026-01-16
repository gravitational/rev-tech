# MySQL Self-Hosted (Teleport)

This example provisions a self-hosted MySQL database on EC2, sets up TLS, and uses the Teleport Database Service to register the database dynamically.

It mirrors the official [Teleport self-hosted MySQL guide](https://goteleport.com/docs/enroll-resources/database-access/enroll-self-hosted-databases/mysql-self-hosted/) and is modularized for reuse.

---

## What It Deploys

- 1 EC2 instance running MySQL (MariaDB) on Ubuntu 22.04
- A custom CA and server TLS certificate for encrypted MySQL access
- Teleport agent with `db_service` and `ssh_service`
- Teleport dynamic discovery enabled via label matching: `tier = dev`

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
tsh db ls --labels=tier=dev
tsh db connect demo-mysql --db-user=alice
```

5. Tear down:
```bash
terraform destroy
```

---

## Notes
- Teleport connects to MySQL using mutual TLS
- Users `alice` and `bob` are created with Teleport cert CN mapping
- `demo-mysql` is registered with the `teleport_database` resource
- Customize with your own CA or plug into SSM for secrets
