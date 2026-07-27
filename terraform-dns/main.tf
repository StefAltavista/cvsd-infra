locals {
  hosted_zone_name = trimsuffix(
    trimspace(var.hosted_zone_name),
    "."
  )

  ingress_hostname = trimsuffix(
    trimspace(var.ingress_hostname),
    "."
  )

  application_records = {
    vote   = "vote.${var.student_name}.${local.hosted_zone_name}"
    result = "result.${var.student_name}.${local.hosted_zone_name}"
  }

  common_tags = {
    Project   = "voting-app"
    Student   = var.student_name
    ManagedBy = "Terraform"
  }
}

# Read the existing public hosted zone.
# Terraform does not create or own ironlabs.online itself.
data "aws_route53_zone" "main" {
  name         = "${local.hosted_zone_name}."
  private_zone = false
}

# Both application hostnames point to the same ingress-nginx load balancer.
# NGINX distinguishes them using the incoming HTTP Host header.
resource "aws_route53_record" "application" {
  for_each = local.application_records

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = local.ingress_hostname
    zone_id                = var.ingress_zone_id
    evaluate_target_health = true
  }
}