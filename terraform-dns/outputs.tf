output "hosted_zone_id" {
  description = "ID of the existing ironlabs.online hosted zone."
  value       = data.aws_route53_zone.main.zone_id
}

output "ingress_hostname" {
  description = "AWS Network Load Balancer targeted by the DNS records."
  value       = local.ingress_hostname
}

output "vote_domain" {
  description = "Public hostname of the vote application."
  value = trimsuffix(
    aws_route53_record.application["vote"].fqdn,
    "."
  )
}

output "result_domain" {
  description = "Public hostname of the result application."
  value = trimsuffix(
    aws_route53_record.application["result"].fqdn,
    "."
  )
}

output "vote_url" {
  description = "Current HTTP URL of the vote application."
  value = "http://${trimsuffix(
    aws_route53_record.application["vote"].fqdn,
    "."
  )}"
}

output "result_url" {
  description = "Current HTTP URL of the result application."
  value = "http://${trimsuffix(
    aws_route53_record.application["result"].fqdn,
    "."
  )}"
}