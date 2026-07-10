# Standalone Control Plane — Layer 1: Cluster

Provisions the VPC, subnets, security groups, IAM instance profile, and S3 state bucket. Shared infrastructure consumed by layers 2 and 3 via `terraform_remote_state`.

See [../README.md](../README.md) for the full standalone control plane deployment guide and layer sequence.
