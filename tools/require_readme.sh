#!/usr/bin/env bash
# Fail the PR if any touched folder under $ROOTS lacks a README.md (case-insensitive).
# Usage (CI): ROOTS="use-cases proof-of-concepts templates integrations" ./tools/testing/require-readme.sh
set -euo pipefail

ROOTS="${ROOTS:-use-cases proof-of-concepts templates integrations tools}"
IFS=' ' read -r -a ROOTS_ARR <<< "$ROOTS"

# Base commit (optional arg or env). Falls back to origin/$GITHUB_BASE_REF or merge-base.
base="${1:-${BASE_SHA:-}}"
if [[ -z "$base" ]]; then
  git fetch --no-tags --prune --depth=1 origin "${GITHUB_BASE_REF:-main}" || true
  base="$(git rev-parse "origin/${GITHUB_BASE_REF:-main}")"
fi
if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  base="$(git merge-base HEAD "origin/${GITHUB_BASE_REF:-main}")"
fi

git diff -M --name-status "$base" HEAD > /tmp/changes.txt || true

declare -A touched_non_deleted=()

while IFS=$'\t' read -r status f1 f2; do
  [[ -z "${status:-}" ]] && continue
  path="$f1"; non_deleted=1
  if [[ "$status" == R* || "$status" == C* ]]; then path="$f2"; non_deleted=1; fi
  if [[ "$status" == D* ]]; then path="$f1"; non_deleted=0; fi

  IFS='/' read -r top second _ <<< "$path"
  [[ -z "${top:-}" || -z "${second:-}" ]] && continue

  for r in "${ROOTS_ARR[@]}"; do
    [[ "$top" == "$r" ]] || continue
    [[ $non_deleted -eq 1 ]] && touched_non_deleted["$top/$second"]=1
  done
done < /tmp/changes.txt

if [[ ${#touched_non_deleted[@]} -eq 0 ]]; then
  echo "No added/modified files in enforced folders; skipping."
  exit 0
fi

missing=()
for slug in "${!touched_non_deleted[@]}"; do
  if find "$slug" -maxdepth 1 -type f -iname 'README.md' | grep -q .; then
    echo "README present in $slug"
  else
    echo "README missing in $slug"
    missing+=("$slug/README.md")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'Missing README files:\n'; printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "All touched folders contain a README"
