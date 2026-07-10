# IAM security invariants for Teleport demo templates.
#
# Teleport demos use IAM roles for instance profiles and cross-account access.
# These rules catch the most common IAM mistakes that would embarrass an SE
# in front of a security-focused prospect.

package teleport_demo.iam

import rego.v1

# ---------------------------------------------------------------------------
# IAM roles must not use a wildcard principal ("*") in their trust policy.
# This would allow any AWS account or service to assume the role.
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_role"
	resource.change.actions[_] in ["create", "update"]

	# Parse the assume_role_policy JSON string.
	policy := json.unmarshal(resource.change.after.assume_role_policy)
	statement := policy.Statement[_]
	statement.Effect == "Allow"

	# Check for wildcard principal.
	principal := statement.Principal
	is_wildcard_principal(principal)

	msg := sprintf(
		"[IAM] %s trust policy allows wildcard principal (*). Scope the trust to specific services or accounts.",
		[resource.address],
	)
}

is_wildcard_principal(principal) if principal == "*"

is_wildcard_principal(principal) if principal.AWS == "*"

is_wildcard_principal(principal) if principal.Service == "*"

# ---------------------------------------------------------------------------
# Inline IAM policies must not grant AdministratorAccess via Action: "*".
# Demo templates use scoped IAM policies for the AWS Console app.
# A wildcard action on inline policies is a red flag for security prospects.
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_role_policy"
	resource.change.actions[_] in ["create", "update"]

	policy := json.unmarshal(resource.change.after.policy)
	statement := policy.Statement[_]
	statement.Effect == "Allow"

	# Either Action or Resource is "*" in a non-managed-policy inline attachment.
	statement.Action == "*"
	statement.Resource == "*"

	msg := sprintf(
		"[IAM] %s grants Action:* on Resource:* — this is equivalent to AdministratorAccess on an inline policy.",
		[resource.address],
	)
}
