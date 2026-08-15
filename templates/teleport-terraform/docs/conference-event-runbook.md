# Conference Event Runbook

How to stand up, run, and tear down a booth demo environment built from
`profiles/presets/conference.tfvars`. Every item here was learned the hard way
at a live event; the fixes that could live in code are in this repo already.

## Build (before the event)

- Deploy from the preset. Set `profile_label` per event (resource tags), then:
  `tsh login --proxy=<event-cluster>`, `eval $(tctl terraform env)`,
  `terraform apply -var-file=presets/conference.tfvars`. Read the
  `connection_guide` and `demo_user_setup` outputs.
- Commit preset changes the day you make them. Presets are tracked
  (`!profiles/presets/*.tfvars`); do not let event config live on one laptop.
- Keep terraform state off the laptop: remote backend in the event's region,
  or at minimum a daily copy.
- Land ALL SSO connector role-mapping changes at build time, not mid-event.
  They live with the control-plane owner and need review lead time.
- Demo personas: one per station (a `tctl lock --user` is cluster-wide, so a
  shared persona kills both stations). Enroll each persona's MFA on its own
  station hardware, early. Keep the cluster at `second_factor: on` (webauthn
  preferred, TOTP allowed) so rehearsal in a VM stays possible.
- Build booth Macs with `tools/demo-mac-setup/`. Rehearse the build on a
  factory-fresh macOS VM first; a clean-slate run catches bugs a lived-in
  machine hides.
- Official signed tsh only on demo machines: Device Trust and hardware-key
  webauthn reject community builds (setup.sh installs the pkg).

## Every morning

```
PROXY=<event-cluster> ./tools/conference-preflight.sh
```

Zero FAILs before the first demo. The script does a live request cycle,
checks one-app-server-per-app, probes the MCP allowlist end to end, and
sweeps stale locks left by rehearsals.

## During the event

- Check every `terraform plan` for replacements before applying. Instance
  modules pin the AMI (`ignore_changes`), but the habit stays: an upstream
  AMI bump must never replace a healthy fleet mid-event.
- Never live-edit an agent's teleport.yaml over its own tunnel. Replace
  stateless nodes with `terraform apply -replace=...` instead.
- Demo MCP with MCP Inspector, not an AI client. Teleport filters denied
  tools out of tools/list, so an AI client shows no visible denial; Inspector
  puts the per-identity toolset difference on one screen.

## Teardown (the order matters)

1. Strip terraform-managed roles from any NON-terraform users that hold them
   (`tctl users update --set-roles ...`), or role deletion fails with
   "role is still in use by a user".
2. Remove the demo role names from the SSO connector mappings (control-plane
   repo PR) and verify with `tctl get saml/<connector>` BEFORE deleting
   roles. Deleting a role the connector still maps breaks every SSO login
   with "role not found".
3. `terraform destroy -var-file=presets/conference.tfvars` for the data plane.
4. Only then should the control-plane owner delete the cluster and DNS.
5. If the control plane dies first, the leftovers are orphans:
   `terraform state rm` them and verify `terraform state list` is empty.
