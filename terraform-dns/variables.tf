variable "region" {
  description = "AWS region containing the ingress Network Load Balancer."
  type        = string
  default     = "us-east-1"
}

variable "hosted_zone_name" {
  description = "Existing public Route 53 hosted zone."
  type        = string
  default     = "ironlabs.online"
}

variable "student_name" {
  description = "Student-specific subdomain segment."
  type        = string
  default     = "stef"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.student_name))
    error_message = "student_name may contain only lowercase letters, numbers, and hyphens."
  }
}

variable "ingress_hostname" {
  description = "DNS hostname of the ingress-nginx AWS Network Load Balancer."
  type        = string

  validation {
    condition = can(
      regex(
        "^[A-Za-z0-9.-]+$",
        var.ingress_hostname
      )
    )

    error_message = "ingress_hostname must be a DNS hostname without http://, https://, or a path."
  }
}

variable "ingress_zone_id" {
  description = "Canonical hosted zone ID of the ingress-nginx AWS Network Load Balancer."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.ingress_zone_id))
    error_message = "ingress_zone_id must be an AWS canonical hosted zone ID beginning with Z."
  }
}