# teleport-terraform tools

Helper scripts for validating and testing templates in this directory.

## Scripts

- `terraform-templates-check.sh` – runs `terraform fmt -check` and `terraform validate` per template. Supports optional plans with `RUN_TERRAFORM_PLAN=1` (requires AWS + Teleport credentials).
- `smoke-test.sh` – apply/verify/destroy a single template. Usage: `./smoke-test.sh server-access-ssh-getting-started` (uses `tsh` to verify by label; templates without a verify rule are applied/destroyed with verification skipped).
- `smoke-test-all.sh` – runs `smoke-test.sh` across `data-plane/` templates and prints a summary (`--quick` or `--full`).

## Batch smoke examples

Run quick suite:

```bash
./tools/smoke-test-all.sh --quick
```

Run full suite:

```bash
./tools/smoke-test-all.sh --full
```

Run only selected templates:

```bash
./tools/smoke-test-all.sh --templates=server-access-ssh-getting-started,application-access-aws-console
```

Keep resources for inspection:

```bash
./tools/smoke-test-all.sh --no-destroy
```
