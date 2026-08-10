# Route53 hosted zone (only when we manage DNS)
resource "aws_route53_zone" "this" {
  count = var.dns_mode == "self_managed" ? 1 : 0
  name  = var.domain_name
  tags  = var.tags
}
