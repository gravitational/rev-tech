#!/usr/bin/env bash
# Demo Mac setup: software plus the demo-specific pieces brew can't do.
# Mirrors the per-station prep in docs/conference-event-runbook.md. Run as the demo
# user; no sudo needed except what the Homebrew installer itself asks for.
set -uo pipefail
cd "$(dirname "$0")"

# Non-login shells (ssh one-liners, some automation) miss these; the Teleport
# pkg installs to /usr/local/bin and brew to /opt/homebrew/bin.
export PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"

# --- 1. Homebrew + packages ---
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
brew update
brew bundle --file=Brewfile

# --- 2. Teleport client tools (tsh, tctl) ---
# Deliberately NOT from brew: Device Trust and hardware-key webauthn require
# Teleport's signed build. Match the cluster's major version.
TELEPORT_VERSION="18.10.0"
if ! command -v tsh >/dev/null 2>&1; then
  echo "Installing official Teleport client pkg ${TELEPORT_VERSION} (sudo will prompt)..."
  curl -fsSLo "/tmp/teleport-${TELEPORT_VERSION}.pkg" "https://cdn.teleport.dev/teleport-${TELEPORT_VERSION}.pkg"
  sudo installer -pkg "/tmp/teleport-${TELEPORT_VERSION}.pkg" -target /
  rm -f "/tmp/teleport-${TELEPORT_VERSION}.pkg"
fi
if ! codesign -dv "$(command -v tsh)" 2>&1 | grep -q QH8AA5B8UP; then
  echo "!! tsh is not the official signed build."
  echo "   Install the macOS pkg from https://goteleport.com/download/ (or use Teleport Connect's bundled tsh)."
fi

# --- 3. Pre-cache MCP Inspector (Section 8; conference Wi-Fi is not your friend) ---
npm install -g @modelcontextprotocol/inspector

# --- 4. Verify the build ---
echo "--- BUILD VERIFICATION ---"
MISSING=0
for c in tsh tctl kubectl k9s helm psql mysql aws az gcloud nvim node jq claude; do
  if command -v "$c" >/dev/null 2>&1; then
    printf 'OK       %-8s %s\n' "$c" "$(command -v "$c")"
  else
    printf 'MISSING  %s\n' "$c"; MISSING=$((MISSING+1))
  fi
done
npm ls -g --depth=0 2>/dev/null | grep -q '@modelcontextprotocol/inspector' \
  && echo "OK       mcp-inspector (cached)" || { echo "MISSING  mcp-inspector"; MISSING=$((MISSING+1)); }
[ "$MISSING" -eq 0 ] && echo "Build verification: all present." || echo "Build verification: $MISSING missing — fix before imaging this machine."

# --- 5. Manual steps ---
cat <<'EOF'
--- MANUAL STEPS (per station) ---
1. Chrome profile for the station's persona (station 1: bob, station 2: alice).
2. iTerm profile named after the persona; Profiles > Send text at start:
     export TELEPORT_HOME=$HOME/.tsh-bob        (station 2: .tsh-alice)
   Give it a distinct color so nobody demos as the wrong identity.
3. Activate the persona ON THIS MACHINE with its own YubiKey:
     tctl users reset bob
   Open the link in the persona's Chrome profile: set password, add hardware key.
4. Bookmark the event cluster's Web UI in both Chrome profiles
   (plus the backup environment's, if the event has one).
5. Wallpaper, cursor, and login password per the must-haves doc.
EOF
