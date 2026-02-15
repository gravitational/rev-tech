# teleport-terraform tools

Helper scripts for validating and testing templates in this directory.

## Scripts

- `terraform-templates-check.sh` – runs `terraform fmt -check` and `terraform validate` per template. Supports optional plans with `RUN_TERRAFORM_PLAN=1` (requires AWS + Teleport credentials).
- `smoke-test.sh` – apply/verify/destroy a single template. Usage: `./smoke-test.sh application-access-httpbin` (uses `tsh` to verify by label). Set `TF_SMOKE_SSH_LOGIN` (or `TF_VAR_ssh_login`) to control the SSH login used for machine-id checks.
