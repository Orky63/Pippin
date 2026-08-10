locals {
  # Auto-generate description if not provided
  distribution_description = var.distribution_description != "" ? var.distribution_description : "${var.name}-cdn"

  tags = merge(
    { ManagedBy = "terraform" },
    var.tags,
  )

  # API Gateway HTTP API domain (used as a single CloudFront origin).
  # Format: {api_id}.execute-api.{region}.amazonaws.com
  api_domain = local.api_needed ? "${aws_apigatewayv2_api.this[0].id}.execute-api.${data.aws_region.current.region}.amazonaws.com" : null

  spa_error_responses = var.spa_mode ? {
    for code in [403, 404] : tostring(code) => {
      error_code            = code
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 300
    }
  } : {}

  static_error_responses = var.static_error_response_page_path != null ? {
    for code in var.static_error_response_codes : tostring(code) => {
      error_code            = code
      response_code         = var.static_error_response_code
      response_page_path    = var.static_error_response_page_path
      error_caching_min_ttl = var.static_error_caching_min_ttl
    }
  } : {}

  custom_error_responses = merge(local.spa_error_responses, local.static_error_responses)
}

data "aws_region" "current" {}
