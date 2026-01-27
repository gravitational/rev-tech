#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <template-dir> [--no-destroy] [--skip-verify]" >&2
  exit 1
fi

template_dir="$1"
shift

no_destroy=0
skip_verify=0

for arg in "$@"; do
  case "$arg" in
    --no-destroy)
      no_destroy=1
      ;;
    --skip-verify)
      skip_verify=1
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
templates_root=$(cd "${script_dir}/.." && pwd)
workdir="${templates_root}/${template_dir}"

if [[ ! -d "${workdir}" ]]; then
  echo "template directory not found: ${workdir}" >&2
  exit 1
fi

if [[ ! -f "${workdir}/main.tf" ]]; then
  echo "no main.tf found in ${workdir}" >&2
  exit 1
fi

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

if ! env | grep -q '^TF_TELEPORT_' && ! env | grep -q '^TELEPORT_' ; then
  echo "Teleport Terraform credentials not found; run: tsh login --proxy=<cluster> && eval \\$(tctl terraform env)" >&2
  exit 1
fi

cleanup() {
  if [[ ${no_destroy} -eq 0 ]]; then
    (cd "${workdir}" && terraform destroy -auto-approve)
  fi
}
trap cleanup EXIT

(cd "${workdir}" && terraform init -backend=false)
(cd "${workdir}" && terraform plan -input=false)
(cd "${workdir}" && terraform apply -auto-approve)

if [[ ${skip_verify} -eq 0 ]]; then
  env_label="${TF_VAR_env:-dev}"
  case "${template_dir}" in
    application-access-*)
      tsh apps ls env=${env_label}
      ;;
    database-access-*)
      tsh db ls env=${env_label}
      ;;
    server-access-ssh-getting-started)
      tsh ls env=${env_label}
      ;;
    desktop-access-*)
      tsh desktop ls
      ;;
    machine-id-ansible)
      tsh ls env=${env_label}
      ;;
    machine-id-mcp)
      tsh mcp ls
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
