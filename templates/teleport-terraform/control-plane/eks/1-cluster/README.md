# EKS Control Plane — Layer 1: Cluster

Provisions the EKS cluster, VPC, and supporting AWS infrastructure (node groups, IAM roles, OIDC provider). All subsequent layers read this layer's state via `terraform_remote_state`.

See [../README.md](../README.md) for the full EKS control plane deployment guide and layer sequence.
