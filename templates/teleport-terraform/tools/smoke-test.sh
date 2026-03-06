#!/usr/bin/env bash
set -euo pipefail

# Smoke test a single template: plan/apply, verify in Teleport, and destroy.

# Parse required positional arg and optional flags.
if [[ $# -lt 1 ]]; then
  echo "usage: $0 <template-dir> [--no-destroy] [--skip-verify] [--ssh-login=<login>] [--verify-timeout=<seconds>] [--verify-interval=<seconds>]" >&2
  echo "example: $0 data-plane/server-access-ssh-getting-started" >&2
  exit 1
fi

template_dir="$1"
shift

no_destroy=0
skip_verify=0
ssh_login_arg=""
verify_timeout_arg=""
verify_interval_arg=""

# Basic flag parsing (no short options to keep it simple).
for arg in "$@"; do
  case "$arg" in
    --no-destroy)
      no_destroy=1
      ;;
    --skip-verify)
      skip_verify=1
      ;;
    --ssh-login=*)
      ssh_login_arg="${arg#*=}"
      ;;
    --verify-timeout=*)
      verify_timeout_arg="${arg#*=}"
      ;;
    --verify-interval=*)
      verify_interval_arg="${arg#*=}"
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

# Resolve paths relative to this script to avoid CWD issues.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
templates_root=$(cd "${script_dir}/.." && pwd)

# Allow passing a bare template name by resolving under data-plane/.
if [[ "${template_dir}" != */* ]]; then
  if [[ -d "${templates_root}/data-plane/${template_dir}" ]]; then
    template_dir="data-plane/${template_dir}"
  fi
fi

workdir="${templates_root}/${template_dir}"

# Sanity checks for the template directory.
if [[ ! -d "${workdir}" ]]; then
  echo "template directory not found: ${workdir}" >&2
  exit 1
fi

if [[ ! -f "${workdir}/main.tf" ]]; then
  echo "no main.tf found in ${workdir}" >&2
  exit 1
fi

# Ensure required CLIs are available before running Terraform.
if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is not installed or not on PATH" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found; ensure AWS credentials are available" >&2
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "AWS credentials not available in this shell" >&2
  exit 1
fi

# Optional Teleport verification via tsh.
if [[ ${skip_verify} -eq 0 ]]; then
  if ! command -v tsh >/dev/null 2>&1; then
    echo "tsh not found; use --skip-verify to skip Teleport checks" >&2
    exit 1
  fi
  if ! tsh status >/dev/null 2>&1; then
    echo "Teleport login not detected; run: tsh login --proxy=<cluster>" >&2
    exit 1
  fi
  if tsh status 2>/dev/null | grep -q "EXPIRED"; then
    echo "Teleport login expired; run: tsh login --proxy=<cluster>" >&2
    exit 1
  fi
fi

# Teleport Terraform provider credentials must be present for apply/plan.
if ! env | grep -q '^TF_TELEPORT_' && ! env | grep -q '^TELEPORT_' ; then
  echo "Teleport Terraform credentials not found; run: tsh login --proxy=<cluster> && eval \\$(tctl terraform env)" >&2
  exit 1
fi

# Always destroy unless explicitly disabled.
cleanup() {
  if [[ ${no_destroy} -eq 0 ]]; then
    (cd "${workdir}" && terraform destroy -auto-approve)
  fi
}
trap cleanup EXIT

# Use a local backend for smoke tests and avoid touching remote state.
(cd "${workdir}" && terraform init -backend=false)
(cd "${workdir}" && terraform plan -input=false)
(cd "${workdir}" && terraform apply -auto-approve)

if [[ ${skip_verify} -eq 0 ]]; then
  env_label="${TF_VAR_env:-dev}"
  team_label="${TF_VAR_team:-platform}"
  ssh_login="${ssh_login_arg:-${TF_SMOKE_SSH_LOGIN:-${TF_VAR_ssh_login:-ec2-user}}}"
  verify_timeout="${verify_timeout_arg:-${TF_SMOKE_VERIFY_TIMEOUT_SECONDS:-180}}"
  verify_interval="${verify_interval_arg:-${TF_SMOKE_VERIFY_INTERVAL_SECONDS:-10}}"
  case "${template_dir}" in
    application-access-aws-console|*/application-access-aws-console)
      expected_apps_json=$(cd "${workdir}" && terraform output -json apps 2>/dev/null || echo "[]")
      expected_apps=$(echo "${expected_apps_json}" | tr -d '[]"' | tr ',' '\n' | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [[ -z "${expected_apps}" ]]; then
        echo "no expected apps returned by terraform output 'apps'" >&2
        exit 1
      fi

      apps_out=$(tsh apps ls env=${env_label},team=${team_label} --format=names || true)
      while IFS= read -r expected_app; do
        [[ -z "${expected_app}" ]] && continue
        if ! grep -qx "${expected_app}" <<< "${apps_out}"; then
          echo "expected app ${expected_app} in env=${env_label},team=${team_label}" >&2
          tsh apps ls env=${env_label},team=${team_label} || true
          exit 1
        fi
      done <<< "${expected_apps}"
      ;;
    application-access-*|*/application-access-*)
      tsh apps ls env=${env_label},team=${team_label}
      ;;
    database-access-*|*/database-access-*)
      tsh db ls env=${env_label},team=${team_label}
      ;;
    server-access-ssh-getting-started|*/server-access-ssh-getting-started)
      tsh ls env=${env_label},team=${team_label}
      ;;
    desktop-access-*|*/desktop-access-*)
      echo "desktop verification skipped: this tsh build has no desktop list command" >&2
      ;;
    machine-id-ansible|*/machine-id-ansible)
      # Give Teleport time to register the node before asserting readiness.
      nodes=""
      elapsed=0
      while [[ ${elapsed} -le ${verify_timeout} ]]; do
        nodes=$(tsh ls env=${env_label},team=${team_label} --format=names || true)
        if [[ -n "${nodes}" ]]; then
          break
        fi
        echo "waiting for nodes (env=${env_label}, team=${team_label})... ${elapsed}s/${verify_timeout}s"
        sleep "${verify_interval}"
        elapsed=$((elapsed + verify_interval))
      done
      if [[ -z "${nodes}" ]]; then
        echo "no nodes found for env=${env_label}, team=${team_label} after ${verify_timeout}s" >&2
        exit 1
      fi
      while IFS= read -r node; do
        [[ -z "${node}" ]] && continue
        echo "checking tbot on ${node}"
        if ! tsh ssh -l "${ssh_login}" "${node}" -- "sudo systemctl is-active tbot"; then
          echo "tbot is not active on ${node}; collecting diagnostics..." >&2
          tsh ssh -l "${ssh_login}" "${node}" -- "sudo systemctl status tbot --no-pager -l || true"
          tsh ssh -l "${ssh_login}" "${node}" -- "sudo journalctl -u tbot -n 200 --no-pager || true"
          tsh ssh -l "${ssh_login}" "${node}" -- "sudo cat /etc/tbot.yaml || true"
          exit 1
        fi
        echo "checking /opt/machine-id/ssh_config on ${node}"
        if ! tsh ssh -l "${ssh_login}" "${node}" -- "test -f /opt/machine-id/ssh_config"; then
          echo "missing /opt/machine-id/ssh_config on ${node}; collecting diagnostics..." >&2
          tsh ssh -l "${ssh_login}" "${node}" -- "ls -la /opt/machine-id || true"
          tsh ssh -l "${ssh_login}" "${node}" -- "sudo journalctl -u tbot -n 200 --no-pager || true"
          tsh ssh -l "${ssh_login}" "${node}" -- "sudo cat /etc/tbot.yaml || true"
          exit 1
        fi
      done <<< "${nodes}"
      ;;
    machine-id-mcp|*/machine-id-mcp)
      mcp_app_name="mcp-filesystem-${env_label}"
      if ! tctl get "app/${mcp_app_name}" >/dev/null 2>&1; then
        echo "expected MCP app ${mcp_app_name} not found in cluster resources" >&2
        tctl get apps || true
        exit 1
      fi
      tsh mcp ls env=${env_label},team=${team_label}
      ;;
    *)
      echo "no verification rule for ${template_dir}; use --skip-verify" >&2
      exit 1
      ;;
  esac
fi

if [[ ${no_destroy} -eq 1 ]]; then
  trap - EXIT
fi
