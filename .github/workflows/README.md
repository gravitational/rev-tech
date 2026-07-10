# GitHub Actions Workflows

| Workflow | Trigger | Description |
|---|---|---|
| `terraform-templates.yml` | push / PR to `templates/teleport-terraform/**` | Runs `terraform fmt`, completeness check, `terraform validate`, and `terraform test` across all templates. |
| `teleport-demo-deploy.yml` | `workflow_dispatch` | One-click demo deployment — pick a profile and environment, provisions all use cases against your Teleport cluster. |
| `teleport-demo-teardown.yml` | `schedule` (Mon 08:00 UTC) + `workflow_dispatch` | Destroys all demo profiles for the target environment. Safety net against runaway AWS costs. |

## Setup

Before the deploy/teardown workflows will run, one-time setup is required:

- AWS OIDC identity provider and IAM role
- Teleport Machine ID bot and GitHub join token
- S3 bucket for Terraform state
- GitHub Actions secrets

See [`docs/github-actions-setup.md`](../docs/github-actions-setup.md) for the full step-by-step guide.
