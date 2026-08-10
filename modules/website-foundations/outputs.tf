output "bucket_name" {
  value = aws_s3_bucket.site.id
}

output "bucket_arn" {
  value = aws_s3_bucket.site.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain for use as CloudFront origin."
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}

output "s3_oac_id" {
  description = "S3 Origin Access Control ID for CloudFront."
  value       = aws_cloudfront_origin_access_control.s3.id
}

output "certificate_arn" {
  description = "ACM certificate ARN. Null when dns_mode is none."
  value = var.dns_mode == "self_managed" ? (
    aws_acm_certificate_validation.this[0].certificate_arn
    ) : var.dns_mode == "external" ? (
    var.certificate_arn
  ) : null
}

output "zone_id" {
  description = "Route53 hosted zone ID. Null unless dns_mode is self_managed."
  value       = try(aws_route53_zone.this[0].zone_id, null)
}

output "name_servers" {
  description = "Route53 NS records for name server cutover. Null unless dns_mode is self_managed."
  value       = try(aws_route53_zone.this[0].name_servers, null)
}

output "validation_records" {
  description = "ACM DNS validation records (CNAME name/value pairs). For self_managed, these are auto-created. For reference only."
  value = var.dns_mode != "none" ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  } : null
}

output "response_headers_policy_id" {
  description = "CloudFront response headers policy ID with security headers + CSP."
  value       = aws_cloudfront_response_headers_policy.security.id
}
