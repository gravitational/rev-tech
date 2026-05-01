# teleport-terraform tools

Helper scripts for validating and testing templates in this directory.

## Scripts

- `terraform-templates-check.sh` – runs `terraform fmt -check` and `terraform validate` per template. Supports optional plans with `RUN_TERRAFORM_PLAN=1` (requires AWS + Teleport credentials).
- `smoke-test.sh` – apply/verify/destroy a single template. Usage: `./smoke-test.sh application-access-httpbin` (uses `tsh` to verify by label). Supports `--ssh-login`, `--verify-timeout`, and `--verify-interval`.
- `smoke-test.sh` prints extra diagnostics for `machine-id-ansible` failures (tbot status, recent journal logs, and `/etc/tbot.yaml`).
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
./tools/smoke-test-all.sh --templates=server-access-ssh-getting-started,machine-id-ansible
```

Tune machine-id readiness checks and login:

```bash
./tools/smoke-test-all.sh --templates=machine-id-ansible --no-destroy --ssh-login=ec2-user --verify-timeout=300 --verify-interval=10
```

Keep resources for inspection:

```bash
./tools/smoke-test-all.sh --no-destroy
```
