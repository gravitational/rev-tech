# Demo Mac Setup

Builds a conference demo Mac (booth Mac Mini or SE laptop) from factory-fresh
macOS to fully provisioned demo station in one unattended run. Proven on a
factory-fresh macOS VM (see `docs/conference-event-runbook.md`).

## Audience and prerequisites

- Anyone setting up demo machines for an event. No prior state needed: the
  script installs Homebrew (and Xcode CLT) itself on a clean machine.
- macOS on Apple Silicon, an admin account, network access.

## Run

```bash
./setup.sh
```

Unattended runs (CI, ssh with passwordless sudo): `NONINTERACTIVE=1 ./setup.sh`.

Expected finish: a `BUILD VERIFICATION` block listing every tool as `OK`
("Build verification: all present."), followed by the per-station manual steps
(persona Chrome/iTerm profiles, YubiKey enrollment, bookmarks).

## What it installs

- `Brewfile`: GUI apps (Teleport Connect, iTerm2, VS Code, Claude, Chrome,
  pgAdmin, DBeaver, ...) and CLIs (kubectl, k9s, helm, psql, mysql, cloud
  CLIs, node, jq).
- Official signed Teleport client pkg (tsh + tctl). Deliberately NOT from
  brew: Device Trust and hardware-key webauthn reject community builds. Pin
  `TELEPORT_VERSION` in setup.sh to your cluster's version.
- MCP Inspector, pre-cached for the MCP demo (conference Wi-Fi is not your
  friend).

## Troubleshooting

- A tool shows MISSING in verification: re-run `brew bundle --file=Brewfile`
  and read its error; keg-only formulas need the `link: true` already set in
  the Brewfile.
- `tsh is not the official signed build`: install the pkg from
  https://goteleport.com/download/ — do not `brew install teleport`.
- On MDM-managed corporate Macs, Chrome/Rectangle may be root-owned by the
  MDM; remove those casks from the Brewfile there (booth machines keep them).

## Owners

Revenue Engineering (see repo CODEOWNERS / #rev-tech).
