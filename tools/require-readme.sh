#!/usr/bin/env bash
# Fail the PR if any touched folder under $ROOTS lacks a *.md (case-insensitive),
# evaluating file presence in the **PR head**.
# CI usage: ROOTS="use-cases proof-of-concepts templates integrations tools" ./tools/require-readme.sh
set -euo pipefail

ROOTS="${ROOTS:-use-cases proof-of-concepts templates integrations tools}"
IFS=' ' read -r -a ROOTS_ARR <<< "$ROOTS"

BASE_REF="${BASE_REF:-${GITHUB_BASE_REF:-main}}"
BASE_REMOTE="${BASE_REMOTE:-upstream}"   # workflow adds this; falls back to origin if missing

echo "Current HEAD (PR head): $(git rev-parse --short HEAD)"

# Resolve base commit from requested remote/ref
if ! git rev-parse --verify --quiet "${BASE_REMOTE}/${BASE_REF}"; then
  echo "Base remote '${BASE_REMOTE}' not found; falling back to 'origin'."
  BASE_REMOTE="origin"
  git fetch --no-tags --prune --depth=1 origin "${BASE_REF}" || true
fi
base="$(git rev-parse "${BASE_REMOTE}/${BASE_REF}")"
echo "Base commit: ${base} (${BASE_REMOTE}/${BASE_REF})"

# Gather changed files between base…HEAD (merge-base(base, HEAD) -> HEAD)
git diff -M --name-status "${base}...HEAD" > /tmp/changes.txt || true

declare -A touched_non_deleted=()

while IFS=$'\t' read -r status f1 f2; do
  [[ -z "${status:-}" ]] && continue

  # Determine the relevant path for this change
  path="$f1"; non_deleted=1
  [[ "$status" == R* || "$status" == C* ]] && { path="$f2"; non_deleted=1; }
  [[ "$status" == D* ]] && { path="$f1"; non_deleted=0; }

  # Extract "<root>/<child>" slug
  IFS='/' read -r top second _ <<< "$path"
  [[ -z "${top:-}" || -z "${second:-}" ]] && continue

  # Enforce only for configured roots
  enforced=0
  for r in "${ROOTS_ARR[@]}"; do
    [[ "$top" == "$r" ]] && { enforced=1; break; }
  done
  [[ $enforced -eq 0 ]] && continue

  # Only consider if the "<root>/<child>" is a directory in the PR head
  [[ -d "$top/$second" ]] || continue

  # Only enforce when there are non-deleted changes in that slug
  [[ $non_deleted -eq 1 ]] && touched_non_deleted["$top/$second"]=1
done < /tmp/changes.txt

if [[ ${#touched_non_deleted[@]} -eq 0 ]]; then
  echo "No added/modified directories in enforced roots; skipping."
  exit 0
fi

echo "Touched contribution folders (PR head):"
for slug in "${!touched_non_deleted[@]}"; do echo " - $slug"; done | sort

missing=()
for slug in "${!touched_non_deleted[@]}"; do
  # Case-insensitive check for *.md in the slug (PR head)
  if find "$slug" -maxdepth 1 -type f -iname '*.md' | grep -q .; then
    echo "✅ README present in $slug"
  else
    echo "❌ README missing in $slug"
    missing+=("$slug/*.md")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  {
    echo "*.md must exist for each touched contribution folder (no need to modify it)."
    echo "Missing:"
    for m in "${missing[@]}"; do echo "  - $m"; done
  } >&2

  # Optional summary in Checks UI
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## README presence check failed"
      echo
      for m in "${missing[@]}"; do echo "- \`$m\`"; done
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
fi

echo "All touched folders contain a README ✅"
