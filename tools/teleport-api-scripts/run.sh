#!/bin/bash
set -e

check_exists() {
    if ! type "$1" >/dev/null 2>&1; then echo "Could not find $1, it will need to be available in your PATH"; exit 1; fi
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

usage() {
  cat <<EOF
Usage: $(basename "$0") -p <teleport proxy address> [-i <identity file path>] [-m] [-t]

  -p  Teleport proxy address (required). If no port is specified, :443 is assumed.
  -i  Optional identity file path.
  -m  Run MAU script (mau.go)
  -t  Run TPR script (tpr.gp)

Examples:
  $(basename "$0") -p example.teleport.sh -m
  $(basename "$0") -p example.teleport.sh:443 -i /path/to/identity -t
  $(basename "$0") -p example.teleport.sh -m -t
EOF
}

# parse arguments
PROXY=""
IDENTITY_FILE=""
RUN_MAU=0
RUN_TPR=0

while getopts ":p:i:mt" opt; do
  case "$opt" in
    p) PROXY="$OPTARG" ;;
    i) IDENTITY_FILE="$OPTARG" ;;
    m) RUN_MAU=1 ;;
    t) RUN_TPR=1 ;;
    \?)
      echo "Unknown option: -$OPTARG"
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

# dependencies
check_exists curl
check_exists go
check_exists git
check_exists jq
check_exists tsh

# check proxy address is set
if [[ -z "${PROXY}" ]]; then
  usage
  echo "The proxy address must be accessible from the location where you run this script."
  exit 1
fi

# add default port 443 if not specified
if [[ "${PROXY}" != *":"* ]]; then
  PROXY="${PROXY}:443"
fi

# handle identity file
IDENTITY_FILE_STANZA=""
if [[ -n "${IDENTITY_FILE}" ]]; then
  if [[ ! -f "${IDENTITY_FILE}" ]]; then
    echo "Specified identity file ${IDENTITY_FILE} could not be read"
    exit 4
  fi
  IDENTITY_FILE_STANZA=" -identity_file ${IDENTITY_FILE}"
else
  VALID_UNTIL=$(tsh status --format json 2>/dev/null | jq -r --arg url "https://${PROXY}" '([.active] | map(select(.profile_url == $url)) | first | .valid_until)')
  if [[ "${VALID_UNTIL}" == "" ]] || [[ "${VALID_UNTIL}" == "null" ]]; then
    echo "It doesn't look like you have a currently active tsh profile for ${PROXY}."
    echo "You should login to Teleport with 'tsh login --proxy ${PROXY}' first and then re-run the script."
    echo "Alternatively, you can provide an identity file on the command line with -i /path/to/identity."
    exit 5
  elif (( $(date +%s) > $(to_epoch "${VALID_UNTIL}") )); then
    echo "It looks like your tsh profile for ${PROXY} has expired, so this script won't be able to log in."
    echo "You should re-login to Teleport with 'tsh login --proxy ${PROXY}' and then re-run the script."
    echo "Alternatively, you can provide an identity file on the command line with -i /path/to/identity."
    exit 6
  fi
fi

# check proxy reachability
URL="https://${PROXY}/v1/webapi/find"
STATUS=$(curl -o /dev/null -fsSL "${URL}" -w %\{http_code\})
if [[ "${STATUS}" != "200" ]]; then
  echo "Could not access proxy using ${URL}, got status ${STATUS}"
  exit 2
fi

# get API version matching server verson
TELEPORT_VERSION=$(curl -fsSL "${URL}" | jq -r .server_version)
TELEPORT_SHA=$(git ls-remote https://github.com/gravitational/teleport "refs/tags/v${TELEPORT_VERSION}" | awk '{print $1}')
if [[ "${TELEPORT_SHA}" == "" ]]; then
  echo "Could not find commit hash for tag v${TELEPORT_VERSION}"
  exit 3
fi

echo "Installing Teleport API dependencies for version ${TELEPORT_VERSION} (hash: ${TELEPORT_SHA})"
go get github.com/gravitational/teleport/api@"${TELEPORT_SHA}"
go mod tidy

# Run scripts based on flags
if [[ "${RUN_MAU}" -eq 1 ]]; then
  echo "Running MAU script"
  go run mau.go -proxy "${PROXY}""${IDENTITY_FILE_STANZA}"
fi

if [[ "${RUN_TPR}" -eq 1 ]]; then
  echo "Running TPR script"
  go run tpr.go -proxy "${PROXY}""${IDENTITY_FILE_STANZA}"
fi