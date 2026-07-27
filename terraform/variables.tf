variable "student_name" {
  description = "Lowercase name used to keep AWS resource names unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.student_name))
    error_message = "student_name may contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "k8s_version" {
  description = "Amazon EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "desired_nodes" {
  description = "Desired number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "max_nodes" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 4
}


# Route 53 variables

variable "domain_name" {
  description = "Public domain used by the voting application."
  type        = string
}

variable "ingress_hostname" {
  description = "AWS load balancer hostname created for ingress-nginx."
  type        = string
}