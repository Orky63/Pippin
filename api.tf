# --------------------------------------------------------------------------
# Shared HTTP API
#
# A single aws_apigatewayv2_api fronts every backend Lambda. Each lambda
# submodule (contact-lambda, payment-lambda) attaches its own integration,
# route, and invoke permission against this API. One API ⇒ one CloudFront
# origin, one DNS name to lock down, one throttle budget.
#
# Origin lockdown:
#   CloudFront injects an `x-origin-secret` custom header on every request
#   it forwards. Browser-facing lambdas read the secret from Secrets Manager
#   at cold-start and reject any request whose header doesn't match. The
#   origin secret is created outside Terraform (pass its ARN via
#   origin_secret_arn). The Stripe webhook is exempt — it must be reachable
#   by Stripe's servers and verifies authenticity cryptographically via
#   `stripe-signature`.
# --------------------------------------------------------------------------

locals {
  api_needed = var.enable_contact_form || var.enable_payments
}

# Removed: origin secret no longer created by module (removed in v3.0.0).
# Orphan from state without destroying in AWS.
removed {
  from = random_password.origin_secret
  lifecycle { destroy = false }
}

removed {
  from = aws_secretsmanager_secret.origin_secret
  lifecycle { destroy = false }
}

removed {
  from = aws_secretsmanager_secret_version.origin_secret
  lifecycle { destroy = false }
}

resource "aws_cloudwatch_log_group" "api" {
  count             = local.api_needed ? 1 : 0
  name              = "/aws/apigateway/${var.name}-api"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_apigatewayv2_api" "this" {
  count         = local.api_needed ? 1 : 0
  name          = "${var.name}-api"
  protocol_type = "HTTP"
  description   = "Backend API for ${var.name} (CloudFront origin)."
  tags          = local.tags

  # No CORS at the API layer — all browser traffic flows through CloudFront
  # under the same origin, so cross-origin headers are unnecessary.
}

resource "aws_apigatewayv2_stage" "default" {
  count       = local.api_needed ? 1 : 0
  api_id      = aws_apigatewayv2_api.this[0].id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags

  default_route_settings {
    throttling_burst_limit   = var.api_throttle_burst
    throttling_rate_limit    = var.api_throttle_rate
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api[0].arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}
