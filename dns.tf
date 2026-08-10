# Route53 alias records pointing to the CloudFront distribution.
# Created only in self_managed mode (we own the hosted zone).

resource "aws_route53_record" "alias_a" {
  for_each = var.dns_mode == "self_managed" ? toset(var.aliases) : toset([])

  zone_id = module.site.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_aaaa" {
  for_each = var.dns_mode == "self_managed" ? toset(var.aliases) : toset([])

  zone_id = module.site.zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
