#!/bin/bash
set -e
check_exists() {
    if ! type $1 2>&1 >/dev/null; then echo "Could not find $1, install it"; exit 1; fi
}
to_epoch() {
  local iso="$1"
  if date -d "$iso" +%s >/dev/null 2>&1; then
    # GNU date (Linux, or macOS with coreutils)
    date -d "$iso" +%s
  else
    # BSD date (macOS): convert -04:00 -> -0400 (and +05:30 -> +0530)
    local bsd_iso
    bsd_iso="$(printf '%s' "$iso" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')"
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd_iso" +%s
  fi
}

check_exists curl
check_exists go
check_exists git
check_exists jq
check_exists tsh

if [[ "$1" == "" ]]; then
    echo "Usage: $(basename $0) <teleport proxy address>"
    echo "The proxy address must be accessible from the location where you run this script"
    exit 1
fi
PROXY=$1
# add default port 443 if not specified
if [[ "${PROXY}" != *":"* ]]; then
    PROXY=${PROXY}:443
fi

VALID_UNTIL=$(tsh status --format json 2>/dev/null | jq -r --arg url "https://${PROXY}" '([.active] + .profiles | map(select(.profile_url == $url)) | first | .valid_until)')
if (( $(date +%s) > $(to_epoch "${VALID_UNTIL}") )); then
  echo "It looks like your tsh profile for ${PROXY} has expired, so this script won't be able to log in."
  echo "You should re-login to Teleport with 'tsh login --proxy ${PROXY}' and then re-run the script."
  exit 4
elif [[ "${VALID_UNTIL}" == "" ]]; then
  echo "It doesn't look like you have an active tsh profile for ${PROXY}."
  echo "You should login to Teleport with 'tsh login --proxy ${PROXY}' first and then re-run the script."
fi

URL="https://${PROXY}/v1/webapi/find"
STATUS=$(curl -o /dev/null -fsSL ${URL} -w %{http_code})
if [[ "${STATUS}" != "200" ]]; then
    echo "Could not access ${URL}, got status ${STATUS}"
    exit 2
fi
TELEPORT_VERSION=$(curl -fsSL ${URL} | jq -r .server_version)
# quietly allow optional override of version for testing
if [[ "$2" != "" ]]; then
    TELEPORT_VERSION=$2
fi

TELEPORT_SHA=$(git ls-remote https://github.com/gravitational/teleport "refs/tags/v${TELEPORT_VERSION}" | awk '{print $1}')
if [[ ${TELEPORT_SHA} == "" ]]; then
    echo "Could not find commit hash for tag v${TELEPORT_VERSION}"
    exit 3
fi
echo "Installing Teleport API dependencies for version ${TELEPORT_VERSION} (hash: ${TELEPORT_SHA})"
go get github.com/gravitational/teleport/api@${TELEPORT_SHA}
go get github.com/gravitational/teleport/api/defaults@${TELEPORT_SHA}
go get github.com/gravitational/teleport/api/types@${TELEPORT_SHA}
go mod tidy

echo "Running MAU script"
go run mau.go -proxy ${PROXY}