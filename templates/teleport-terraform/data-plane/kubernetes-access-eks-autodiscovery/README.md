# Kubernetes Access — EKS Auto-Discovery

Deploys a Teleport agent that automatically discovers and enrolls EKS clusters tagged with `teleport-discovery=enabled`. Uses Teleport's EKS auto-enrollment to create EKS access entries — no `aws-auth` ConfigMap edits, no manual kubeconfig setup.

**Requirements:** Teleport 15+, EKS 1.23+ (access entries API), existing EKS cluster(s) in the same AWS account and region.

---

## What It Deploys

- 1 EC2 instance (t3.small) running Teleport `discovery_service` + `kubernetes_service`
- IAM role with EKS `DescribeCluster`, `ListClusters`, and access entry permissions
- Shared VPC/subnet/security group

**Does not** create EKS clusters — point it at clusters you already have.

---

## Prerequisites

Tag each EKS cluster you want Teleport to discover:

```bash
aws eks tag-resource \
  --resource-arn arn:aws:eks:<REGION>:<ACCOUNT>:cluster/<CLUSTER-NAME> \
  --tags teleport-discovery=enabled
```

Or with the AWS Console: EKS → Cluster → Tags → Add tag `teleport-discovery = enabled`.

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_user=you@company.com
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_teleport_version=18.6.4
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2      # must match where your EKS clusters live

cd data-plane/kubernetes-access-eks-autodiscovery
terraform init
terraform apply
```

Allow ~2 minutes for the agent to boot. Tagged clusters enroll within ~30 seconds.

---

## Verify

```bash
tsh kube ls                          # enrolled clusters appear
tsh kube login <cluster-name>
kubectl get nodes                    # uses Teleport-issued kubeconfig
```

---

## Demo: Zero-Touch Enrollment

Show that tagging is all it takes:

```bash
# Tag the cluster
aws eks tag-resource \
  --resource-arn arn:aws:eks:us-east-2:123456789012:cluster/my-cluster \
  --tags teleport-discovery=enabled

# Watch it appear
watch -n 5 tsh kube ls
```

Once enrolled, users access the cluster via Teleport with short-lived kubeconfig credentials — no `aws eks update-kubeconfig`, no static kubeconfig files distributed to users.

---

## RBAC

Teleport creates an EKS access entry for the Teleport IAM role. Users accessing the cluster get Kubernetes groups based on their Teleport roles:

```yaml
# Example Teleport role granting EKS access
spec:
  allow:
    kubernetes_labels:
      env: ["dev"]
    kubernetes_groups: ["system:masters"]
    kubernetes_resources:
      - kind: "*"
        namespace: "*"
        name: "*"
        verbs: ["*"]
```

---

## Teardown

```bash
terraform destroy
```

The agent's EKS access entries are removed on destroy. The EKS clusters themselves are unaffected.

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `proxy_address` | Teleport proxy hostname | **required** |
| `user` | Your email — used for tagging | **required** |
| `teleport_version` | Teleport version | **required** |
| `env` | Environment label | `"dev"` |
| `team` | Team label | `"platform"` |
| `region` | AWS region (must match EKS clusters) | `"us-east-2"` |
| `eks_tag_key` | AWS tag key for cluster discovery | `"teleport-discovery"` |
| `eks_tag_value` | AWS tag value for cluster discovery | `"enabled"` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
