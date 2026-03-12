# aws region to deploy cluster into
variable "region" {
  description = "Name of AWS region to run resources in"
  default     = "us-east-2" # replace with your preferred aws region
  type        = string
}

# used for tracking resources
variable "name" {
  description = "Name of the EKS deployment — used as a prefix for the cluster name (<name>-cluster) and resource tags"
  type        = string
}

# used for tracking resources
variable "user" {
  description = "Name of the user (e.g., john@example.com) managing the deployment"
  type        = string
}

# k8s cluster version
variable "ver_cluster" {
  description = "Version number (e.g.,1.35) of kubernetes to run on the cluster"
  type        = string
}
