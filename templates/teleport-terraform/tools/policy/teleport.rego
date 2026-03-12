# Teleport resource invariants for Teleport demo templates.
#
# These policies enforce Teleport-specific conventions across all templates.

package teleport_demo.teleport

import rego.v1

# ---------------------------------------------------------------------------
# All Teleport resources must carry env and team labels.
# These labels are the basis of the RBAC model — missing labels mean resources
# won't show up under any role's access policy.
# ---------------------------------------------------------------------------
required_labels := {"env", "team"}

deny contains msg if {
	resource := input.resource_changes[_]
	resource.type in [
		"teleport_node",
		"teleport_database",
		"teleport_app",
		"teleport_windows_desktop",
	]
	resource.change.actions[_] in ["create", "update"]

	labels := object.get(resource.change.after, "spec", {})
	label_keys := {k | labels.labels[k]}
	missing := required_labels - label_keys

	count(missing) > 0

	msg := sprintf(
		"[Labels] %s is missing required labels: %v",
		[resource.address, missing],
	)
}

# ---------------------------------------------------------------------------
# Provision tokens must have a role set.
# An empty roles list would result in a token that registers nothing, which
# is always a configuration mistake in demo templates.
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "teleport_provision_token"
	resource.change.actions[_] in ["create", "update"]

	spec := object.get(resource.change.after, "spec", {})
	count(object.get(spec, "roles", [])) == 0

	msg := sprintf(
		"[Token] %s has an empty roles list — the token will not register any services",
		[resource.address],
	)
}
