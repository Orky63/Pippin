data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# CloudWatch Logs group (created explicitly so we control retention)
resource "aws_cloudwatch_log_group" "contact" {
  name              = "/aws/lambda/${var.name}-contact"
  retention_in_days = 14
  tags              = var.tags
}

# IAM role for Lambda
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

data "aws_iam_policy_document" "inline" {
  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.contact.arn}:*"]
  }

  statement {
    sid     = "SendEmail"
    effect  = "Allow"
    actions = ["ses:SendEmail"]
    resources = [
      "arn:aws:ses:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:identity/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.from_email]
    }
  }
}

resource "aws_iam_role" "contact" {
  name               = "${var.name}-contact-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "contact" {
  name   = "inline"
  role   = aws_iam_role.contact.id
  policy = data.aws_iam_policy_document.inline.json
}

resource "aws_lambda_function" "contact" {
  filename         = var.bundle_zip
  function_name    = "${var.name}-contact"
  role             = aws_iam_role.contact.arn
  handler          = "index.handler"
  runtime          = var.runtime
  architectures    = [var.architecture]
  memory_size      = var.memory_size
  timeout          = var.timeout
  source_code_hash = filebase64sha256(var.bundle_zip)

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      FROM_EMAIL = var.from_email
      TO_EMAIL   = var.to_email
    }
  }

  tracing_config { mode = "Active" }
  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.contact]
}

# --------------------------------------------------------------------------
# Wire into the shared HTTP API: POST /api/contact
# --------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "contact" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact" {
  api_id    = var.api_id
  route_key = "POST /api/contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact.id}"
}

resource "aws_lambda_permission" "contact_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}
