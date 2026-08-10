output "bucket_name" {
  description = "S3 website bucket name. Used by CI to sync static assets."
  value       = module.site.bucket_name
}

output "distribution_id" {
  description = "CloudFront distribution ID. Used by CI for cache invalidation."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_domain" {
  description = "CloudFront distribution domain (*.cloudfront.net). Use as CNAME target."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront hosted zone ID for Route53 alias records."
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "website_url" {
  description = "Primary URL of the deployed website."
  value       = var.dns_mode == "none" ? "https://${aws_cloudfront_distribution.this.domain_name}" : "https://${var.aliases[0]}"
}

output "name_servers" {
  description = "Route53 NS records. Provide to client for name server cutover (self_managed mode only)."
  value       = module.site.name_servers
}

output "cert_validation_records" {
  description = "ACM DNS validation CNAMEs. Required when dns_mode is self_managed (auto-created) or as reference when using external mode."
  value       = module.site.validation_records
}

output "contact_api_path" {
  description = "CloudFront path for the contact form endpoint."
  value       = var.enable_contact_form ? "/api/contact" : null
}

output "payment_api_path" {
  description = "CloudFront path for the Stripe payment intent endpoint."
  value       = var.enable_payments ? "/api/stripe/intent" : null
}

output "webhook_api_path" {
  description = "CloudFront path for the Stripe webhook endpoint."
  value       = var.enable_payments ? "/api/stripe/webhook" : null
}

output "github_actions_role_arn" {
  description = "GitHub Actions deploy role ARN. Set as AWS_ROLE_ARN secret in your GitHub repo (only when enable_github_oidc is true)."
  value       = try(module.github_oidc[0].role_arn, null)
}

output "stripe_secrets_arn" {
  description = "Secrets Manager ARN for Stripe credentials (when enable_payments is true)."
  value       = try(module.payments[0].stripe_secrets_arn, null)
}

output "waf_acl_arn" {
  description = "WAF Web ACL ARN (when enable_core_protections is true)."
  value       = try(aws_wafv2_web_acl.core[0].arn, null)
}

output "zone_id" {
  description = "Route53 hosted zone ID (self_managed mode only). Use to add custom DNS records in the same root config."
  value       = module.site.zone_id
}
