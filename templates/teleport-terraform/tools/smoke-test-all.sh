#!/usr/bin/env bash
set -euo pipefail

# Run smoke tests across all data-plane templates (or a selected subset)
# and print a final pass/fail summary.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
templates_root=$(cd "${script_dir}/.." && pwd)
smoke_script="${script_dir}/smoke-test.sh"

if [[ ! -x "${smoke_script}" ]]; then
  echo "missing executable smoke test script: ${smoke_script}" >&2
  exit 1
fi

destroy_flag=""
verify_flag=""
mode="full"
templates_arg=""
ssh_login_arg=""
verify_timeout_arg=""
verify_interval_arg=""

quick_templates="server-access-ssh-getting-started,application-access-httpbin,machine-id-ansible"

usage() {
  cat <<'EOF'
usage: ./tools/smoke-test-all.sh [options]

options:
  --quick                 Run a focused smoke set for fast validation.
  --full                  Run all data-plane smoke tests (default).
  --templates=<list>      Comma-separated template names to run.
                          Example: --templates=machine-id-ansible,application-access-httpbin
  --ssh-login=<login>     SSH login used for machine-id checks (default: ec2-user).
  --verify-timeout=<sec>  Max seconds to wait for machine-id node visibility/readiness.
  --verify-interval=<sec> Seconds between machine-id readiness checks.
  --no-destroy            Keep deployed resources for inspection.
  --skip-verify           Skip tsh verification checks.
  -h, --help              Show this help.

notes:
  - --templates overrides --quick/--full selection.
  - Legacy env var SMOKE_ONLY is still supported.
EOF
}

for arg in "$@"; do
  case "${arg}" in
    --quick)
      mode="quick"
      ;;
    --full)
      mode="full"
      ;;
    --templates=*)
      templates_arg="${arg#*=}"
      ;;
    --ssh-login=*)
      ssh_login_arg="--ssh-login=${arg#*=}"
      ;;
    --verify-timeout=*)
      verify_timeout_arg="--verify-timeout=${arg#*=}"
      ;;
    --verify-interval=*)
      verify_interval_arg="--verify-interval=${arg#*=}"
      ;;
    --no-destroy)
      destroy_flag="--no-destroy"
      ;;
    --skip-verify)
      verify_flag="--skip-verify"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: ${arg}" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Determine template selection:
# 1) --templates (highest precedence)
# 2) SMOKE_ONLY env (backward compatible)
# 3) --quick / --full mode
if [[ -n "${templates_arg}" ]]; then
  smoke_only="${templates_arg}"
elif [[ -n "${SMOKE_ONLY:-}" ]]; then
  smoke_only="${SMOKE_ONLY}"
elif [[ "${mode}" == "quick" ]]; then
  smoke_only="${quick_templates}"
else
  smoke_only=""
fi

mapfile_tmp="${TMPDIR:-/tmp}/smoke-templates.$$"
find "${templates_root}/data-plane" -mindepth 1 -maxdepth 1 -type d | sort > "${mapfile_tmp}"
trap 'rm -f "${mapfile_tmp}"' EXIT

passed=()
failed=()

echo "Running smoke tests from: ${templates_root}/data-plane"
echo "Mode: ${mode}"
if [[ -n "${smoke_only}" ]]; then
  echo "Template filter: ${smoke_only}"
fi

while IFS= read -r dir; do
  template="$(basename "${dir}")"

  if [[ -n "${smoke_only}" ]]; then
    case ",${smoke_only}," in
      *",${template},"*) ;;
      *) continue ;;
    esac
  fi

  echo ""
  echo "==> ${template}"
  if "${smoke_script}" "data-plane/${template}" ${destroy_flag} ${verify_flag} ${ssh_login_arg} ${verify_timeout_arg} ${verify_interval_arg}; then
    passed+=("${template}")
  else
    failed+=("${template}")
  fi
done < "${mapfile_tmp}"

echo ""
echo "Smoke test summary"
echo "------------------"
echo "passed: ${#passed[@]}"
if [[ ${#passed[@]} -gt 0 ]]; then
  for t in "${passed[@]}"; do
    echo "  - ${t}"
  done
fi
echo "failed: ${#failed[@]}"
if [[ ${#failed[@]} -gt 0 ]]; then
  for t in "${failed[@]}"; do
    echo "  - ${t}"
  done
fi

if [[ ${#failed[@]} -gt 0 ]]; then
  exit 1
fi
