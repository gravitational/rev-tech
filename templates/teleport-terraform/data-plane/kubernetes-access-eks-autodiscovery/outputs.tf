output "connection_guide" {
  description = "Quick-reference tsh commands and setup steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Kubernetes Access – EKS Auto-Discovery
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Pre-requisite (run once per target EKS cluster):
      aws eks tag-resource \
        --resource-arn arn:aws:eks:${var.region}:ACCOUNT:cluster/CLUSTER-NAME \
        --tags ${var.eks_tag_key}=${var.eks_tag_value}

    The agent discovers and enrolls tagged clusters within ~60 seconds.
    EKS cluster AWS tags are automatically mapped to Teleport labels.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List discovered Kubernetes clusters:
       tsh kube ls

    3. Login to a cluster:
       tsh kube login <cluster-name>

    4. Run kubectl commands via Teleport:
       tsh kubectl get pods --all-namespaces
       tsh kubectl exec -it <pod-name> -- /bin/bash

    5. Open an interactive session on a pod:
       tsh kubectl exec -it <pod-name> -- /bin/bash

    ──────────────────────────────────────────────────────
    Requirements: Teleport 15+ and EKS 1.23+ (access entries API).
    Discovery tag: ${var.eks_tag_key}=${var.eks_tag_value}
    ──────────────────────────────────────────────────────
  EOT
}

output "agent_instance_id" {
  description = "EC2 instance ID of the Kubernetes discovery agent"
  value       = module.kube_agent.instance_id
}

output "agent_iam_role_arn" {
  description = "IAM role ARN of the agent (for reference or cross-account grants)"
  value       = module.kube_agent.iam_role_arn
}
