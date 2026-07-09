# EC2 instance security invariants for Teleport demo templates.
#
# These policies run against a `terraform show -json` plan file via:
#   conftest test plan.json --policy tools/policy/
#
# Every rule produces a denial message if violated. A passing policy produces
# no output. All rules must pass for CI to succeed.

package teleport_demo.ec2

import rego.v1

# ---------------------------------------------------------------------------
# IMDSv2 must be enforced on all EC2 instances.
# Teleport nodes use the instance metadata endpoint for IAM role credentials
# (e.g., the AWS Console app host). IMDSv2 prevents SSRF attacks from reaching
# the metadata endpoint.
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_instance"
	resource.change.actions[_] in ["create", "update"]

	# http_tokens = "required" enforces IMDSv2.
	metadata := resource.change.after.metadata_options[_]
	metadata.http_tokens != "required"

	msg := sprintf(
		"[IMDSv2] %s must set metadata_options.http_tokens = \"required\"",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# EBS root volumes must be encrypted.
# Teleport nodes can store credentials, certificates, and session data on disk.
# Unencrypted EBS is a compliance red flag in almost every enterprise demo.
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_instance"
	resource.change.actions[_] in ["create", "update"]

	root := resource.change.after.root_block_device[_]
	root.encrypted != true

	msg := sprintf(
		"[EBS] %s root_block_device must have encrypted = true",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# EC2 instances must NOT have public IPs.
# Teleport nodes use outbound reverse tunnels to register with the proxy.
# Public IPs are unnecessary and expand the attack surface.
# ---------------------------------------------------------------------------
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_instance"
	resource.change.actions[_] in ["create", "update"]

	resource.change.after.associate_public_ip_address == true

	msg := sprintf(
		"[PublicIP] %s has associate_public_ip_address = true. Teleport nodes use reverse tunnels; public IPs are not needed.",
		[resource.address],
	)
}

# ---------------------------------------------------------------------------
# Windows instances are exempt from the public IP check above — they receive
# their RDP connections via the Teleport Desktop Service proxy, not direct RDP.
# This rule is a no-op (allows windows_instance resources to be excluded from
# the public IP check via a separate windows policy file if needed).
# ---------------------------------------------------------------------------
