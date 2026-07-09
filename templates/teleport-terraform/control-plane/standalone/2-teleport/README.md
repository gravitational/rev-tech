# Standalone Control Plane — Layer 2: Teleport

Launches a single EC2 instance running both Teleport auth and proxy. Configures Route 53 DNS and ACM TLS. Reads network infrastructure from layer 1 via `terraform_remote_state`.

After apply, run `terraform output initial_user_command` to get the link to create the first admin user.

See [../README.md](../README.md) for the full standalone control plane deployment guide and layer sequence.
