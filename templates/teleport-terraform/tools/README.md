# teleport-terraform tools

Helper scripts for validating and testing templates in this directory.

## Scripts

- `terraform-templates-check.sh` – runs `terraform fmt -check` and `terraform validate` per template. Supports optional plans with `RUN_TERRAFORM_PLAN=1` (requires AWS + Teleport credentials).
