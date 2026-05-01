# Proxy-Peer Control Plane — Layer 2: Teleport

Deploys two EC2 instances: one auth node and one proxy node. Enables proxy peering between them. Configures Route 53 DNS. Reads network infrastructure from layer 1 via `terraform_remote_state`.

After apply, run `terraform output teleport_user_login_details` to get the initial admin user invite link.

See [../README.md](../README.md) for the full proxy-peer control plane deployment guide and layer sequence.
