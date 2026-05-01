# EKS Control Plane — Layer 2: Teleport

Installs Teleport onto the EKS cluster via Helm. Configures cert-manager for TLS, the Teleport auth and proxy services, Route 53 DNS, and an NLB. Optionally enables Access Graph (`var.access_graph_enabled`).

Reads cluster outputs from layer 1 via `terraform_remote_state`.

See [../README.md](../README.md) for the full EKS control plane deployment guide and layer sequence.
