# DynamoDB table for webhook idempotency (prevent duplicate processing)
resource "aws_dynamodb_table" "idempotency" {
  name         = "${var.name}-stripe-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"
  tags         = var.tags

  attribute {
    name = "event_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --------------------------------------------------------------------------
# Payment Lambda  ──  POST /api/stripe/intent
# --------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "payment" {
  name              = "/aws/lambda/${var.name}-stripe-payment"
  retention_in_days = 14
  tags              = var.tags
}

data "aws_iam_policy_document" "payment_inline" {
  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.payment.arn}:*"]
  }

  statement {
    sid       = "RetrieveStripeSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.stripe_secrets_arn]
  }
}

resource "aws_iam_role" "payment" {
  name               = "${var.name}-stripe-payment-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "payment" {
  name   = "inline"
  role   = aws_iam_role.payment.id
  policy = data.aws_iam_policy_document.payment_inline.json
}

resource "aws_lambda_function" "payment" {
  filename         = var.payment_bundle_zip
  function_name    = "${var.name}-stripe-payment"
  role             = aws_iam_role.payment.arn
  handler          = "index.handler"
  runtime          = var.runtime
  architectures    = [var.architecture]
  memory_size      = var.memory_size
  timeout          = var.timeout
  source_code_hash = filebase64sha256(var.payment_bundle_zip)

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = merge(
      { STRIPE_SECRETS_ARN = var.stripe_secrets_arn },
      var.payment_extra_environment,
    )
  }

  tracing_config { mode = "Active" }
  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.payment]
}

resource "aws_apigatewayv2_integration" "payment" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.payment.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "payment" {
  api_id    = var.api_id
  route_key = "POST /api/stripe/intent"
  target    = "integrations/${aws_apigatewayv2_integration.payment.id}"
}

resource "aws_lambda_permission" "payment_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.payment.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}

# --------------------------------------------------------------------------
# Webhook Lambda  ──  POST /api/stripe/webhook
#
# Stripe must reach this endpoint, so it cannot validate the CloudFront
# origin secret. Authenticity is enforced cryptographically by verifying
# the `stripe-signature` header against the webhook secret.
# --------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "webhook" {
  name              = "/aws/lambda/${var.name}-stripe-webhook"
  retention_in_days = 14
  tags              = var.tags
}

data "aws_iam_policy_document" "webhook_inline" {
  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.webhook.arn}:*"]
  }

  statement {
    sid       = "RetrieveStripeSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.stripe_secrets_arn]
  }

  statement {
    sid       = "DynamoDBIdempotency"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.idempotency.arn]
  }
}

resource "aws_iam_role" "webhook" {
  name               = "${var.name}-stripe-webhook-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "webhook" {
  name   = "inline"
  role   = aws_iam_role.webhook.id
  policy = data.aws_iam_policy_document.webhook_inline.json
}

resource "aws_lambda_function" "webhook" {
  filename         = var.webhook_bundle_zip
  function_name    = "${var.name}-stripe-webhook"
  role             = aws_iam_role.webhook.arn
  handler          = "index.handler"
  runtime          = var.runtime
  architectures    = [var.architecture]
  memory_size      = var.memory_size
  timeout          = var.timeout
  source_code_hash = filebase64sha256(var.webhook_bundle_zip)

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = merge(
      {
        STRIPE_SECRETS_ARN = var.stripe_secrets_arn
        IDEMPOTENCY_TABLE  = aws_dynamodb_table.idempotency.name
      },
      var.webhook_extra_environment,
    )
  }

  tracing_config { mode = "Active" }
  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.webhook]
}

resource "aws_apigatewayv2_integration" "webhook" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.webhook.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id    = var.api_id
  route_key = "POST /api/stripe/webhook"
  target    = "integrations/${aws_apigatewayv2_integration.webhook.id}"
}

resource "aws_lambda_permission" "webhook_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}
