#!/usr/bin/env bash
set -euo pipefail

# Resolve paths so the script can run from any working directory.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
templates_root=$(cd "${script_dir}/.." && pwd)

cat <<'HEADER'
terraform-templates-check.sh
--------------------------------
Checks Terraform formatting and validates each template in templates/teleport-terraform.

Requirements:
  - terraform on PATH
  - For RUN_TERRAFORM_PLAN=1:
      * AWS credentials in this shell (e.g., aws sts get-caller-identity works)
      * Teleport Terraform auth exported (eval $(tctl terraform env))
  - For RUN_CONFTEST=1 (policy checks against plan JSON):
      * conftest on PATH (brew install conftest)
      * All RUN_TERRAFORM_PLAN=1 requirements

Usage:
  ./tools/terraform-templates-check.sh
  RUN_TERRAFORM_PLAN=1 ./tools/terraform-templates-check.sh
  RUN_TERRAFORM_PLAN=1 RUN_CONFTEST=1 ./tools/terraform-templates-check.sh
  SKIP_TERRAFORM_INIT=1 ./tools/terraform-templates-check.sh
HEADER

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is not installed or not on PATH" >&2
  exit 1
fi

if [[ ! -d "${templates_root}" ]]; then
  echo "templates root not found: ${templates_root}" >&2
  exit 1
fi

# CI-friendly mode: no interactive prompts from Terraform.
export TF_IN_AUTOMATION=1

# Format check across all templates/modules.
echo "==> terraform fmt -check"
terraform fmt -check -recursive "${templates_root}"

# Discover template directories (any folder with main.tf), excluding modules.
template_dirs="$(
  find "${templates_root}" -path '*/.terraform/*' -prune -o -type f -name 'main.tf' -print \
    | xargs -n1 dirname \
    | sort -u \
    | grep -v '/modules/'
)"

# Completeness check — every template must have README.md and outputs.tf.
# Modules are excluded (they're building blocks, not standalone templates).
echo "==> completeness check (README.md + outputs.tf per template)"
completeness_failed=0
while IFS= read -r dir; do
  [[ -z "${dir}" ]] && continue
  name="${dir##*/}"
  missing=()
  [[ ! -f "${dir}/README.md" ]] && missing+=("README.md")
  [[ ! -f "${dir}/outputs.tf" ]] && missing+=("outputs.tf")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "::error::${name}: missing ${missing[*]}"
    completeness_failed=1
  else
    echo "-- ${name}: ok"
  fi
done <<< "${template_dirs}"
if [[ ${completeness_failed} -ne 0 ]]; then
  echo "completeness check failed — every template needs README.md and outputs.tf" >&2
  exit 1
fi

# Validate each template folder.
echo "==> terraform validate (per template)"
while IFS= read -r dir; do
  [[ -z "${dir}" ]] && continue
  echo "-- ${dir##*/}"
  if [[ "${SKIP_TERRAFORM_INIT:-}" != "1" ]]; then
    # Init per template so validate can resolve providers and modules.
    (cd "${dir}" && terraform init -backend=false -upgrade=false)
  fi
  (cd "${dir}" && terraform validate)
done <<< "${template_dirs}"

# ---------------------------------------------------------------------------
# Run terraform test for any module that has .tftest.hcl files.
# Tests use mock_provider blocks — no real credentials required.
# Requires Terraform >= 1.7.
# ---------------------------------------------------------------------------
echo "==> terraform test (modules with .tftest.hcl)"
test_module_dirs="$(
  find "${templates_root}/modules" -name '*.tftest.hcl' -type f \
    | xargs -n1 dirname \
    | sed 's|/tests$||' \
    | sort -u
)"
if [[ -z "${test_module_dirs}" ]]; then
  echo "-- no .tftest.hcl files found in modules/"
else
  while IFS= read -r dir; do
    [[ -z "${dir}" ]] && continue
    echo "-- ${dir##*/}"
    if [[ "${SKIP_TERRAFORM_INIT:-}" != "1" ]]; then
      (cd "${dir}" && terraform init -backend=false -upgrade=false)
    fi
    (cd "${dir}" && terraform test)
  done <<< "${test_module_dirs}"
fi

if [[ "${RUN_TERRAFORM_PLAN:-}" == "1" ]]; then
  if [[ -z "${TF_VAR_team:-}" ]]; then
    export TF_VAR_team="platform"
  fi
  if ! command -v aws >/dev/null 2>&1; then
    echo "warning: aws CLI not found; plan may fail without credentials" >&2
  else
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      echo "warning: AWS credentials not available; plan may fail" >&2
    fi
  fi
  if ! command -v tctl >/dev/null 2>&1; then
    echo "warning: tctl not found; ensure Teleport Terraform auth is exported" >&2
  fi
  echo "==> terraform plan (per template)"
  while IFS= read -r dir; do
    [[ -z "${dir}" ]] && continue
    echo "-- ${dir##*/}"
    (cd "${dir}" && terraform plan -input=false)
  done <<< "${template_dirs}"
fi

# ---------------------------------------------------------------------------
# Conftest policy checks (optional, requires RUN_TERRAFORM_PLAN=1 first).
#
# Runs OPA policies in tools/policy/ against each template's plan JSON.
# Policies check for: IMDSv2, EBS encryption, no public IPs, Teleport label
# conventions, and IAM wildcard principals.
#
# To run: RUN_TERRAFORM_PLAN=1 RUN_CONFTEST=1 ./tools/terraform-templates-check.sh
# Install conftest: brew install conftest
# ---------------------------------------------------------------------------
if [[ "${RUN_CONFTEST:-}" == "1" ]]; then
  if [[ "${RUN_TERRAFORM_PLAN:-}" != "1" ]]; then
    echo "RUN_CONFTEST=1 requires RUN_TERRAFORM_PLAN=1 to generate plan JSON files first." >&2
    exit 1
  fi
  if ! command -v conftest >/dev/null 2>&1; then
    echo "conftest not found; install with: brew install conftest" >&2
    exit 1
  fi
  policy_dir="${script_dir}/policy"
  echo "==> conftest policy checks (per template)"
  conftest_failed=0
  while IFS= read -r dir; do
    [[ -z "${dir}" ]] && continue
    plan_json="${dir}/plan.json"
    if [[ ! -f "${plan_json}" ]]; then
      # Generate plan JSON inline if not already present.
      (cd "${dir}" && terraform plan -input=false -out=plan.bin -no-color >/dev/null 2>&1)
      (cd "${dir}" && terraform show -json plan.bin > plan.json)
      rm -f "${dir}/plan.bin"
    fi
    echo "-- ${dir##*/}"
    if ! conftest test "${plan_json}" --policy "${policy_dir}" --no-color; then
      conftest_failed=1
    fi
    # Clean up plan JSON — it may contain sensitive values.
    rm -f "${plan_json}"
  done <<< "${template_dirs}"
  if [[ ${conftest_failed} -ne 0 ]]; then
    echo "conftest: one or more policy checks failed" >&2
    exit 1
  fi
fi

cat <<'NOTE'

NOTE: terraform init may download providers; ensure network access or run once with provider cache.
Set SKIP_TERRAFORM_INIT=1 to skip init if already initialized.
Set RUN_TERRAFORM_PLAN=1 to run terraform plan per template (requires credentials).
Set RUN_CONFTEST=1 (with RUN_TERRAFORM_PLAN=1) to run OPA policy checks via conftest.
NOTE
