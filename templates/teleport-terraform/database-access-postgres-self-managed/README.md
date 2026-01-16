# Postgres Self-Hosted Demo

This example demonstrates deploying a self-hosted PostgreSQL database on EC2 and integrating it with Teleport's Database Access via certificate-based authentication.

It mirrors the official [Teleport self-hosted Postgres guide](https://goteleport.com/docs/enroll-resources/database-access/enroll-self-hosted-databases/postgres-self-hosted/) and is modularized for reuse.

## Overview

- Launches a PostgreSQL 15 EC2 instance with TLS enabled
- Installs and configures Teleport on the instance
- Registers the database with Teleport using the `teleport_database` resource
- Uses a custom CA to sign the Postgres server certificate
- Provides Teleport access to roles like `reader` and `writer` using CN-matching

## Files

- `main.tf`: Terraform configuration for deploying the EC2 instance and registering it with Teleport
- `userdata.tpl`: Cloud-init script for configuring PostgreSQL and Teleport on boot

## Requirements

- Terraform CLI
- AWS credentials
- Teleport Enterprise proxy running and accessible
- `teleport_db_ca.pem` exported from your Teleport cluster via `/webapi/auth/export`

## Inputs

Update `main.tf` with values appropriate to your environment:

- `ami_id`: Valid Amazon Linux 2023 or RHEL-based AMI that supports PostgreSQL 15
- `subnet_id`: Subnet to deploy the instance into
- `security_group_ids`: Security group(s) allowing outbound to Teleport Proxy (443) and SSH (22)
- `proxy_address`: Your Teleport Proxy domain (e.g., `teleport.example.com`)
- `teleport_db_ca`: The Teleport CA used for database access

## Usage

```bash
terraform init
terraform apply
