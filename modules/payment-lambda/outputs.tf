output "payment_function_arn" {
  value = aws_lambda_function.payment.arn
}

output "payment_function_name" {
  value = aws_lambda_function.payment.function_name
}

output "webhook_function_arn" {
  value = aws_lambda_function.webhook.arn
}

output "webhook_function_name" {
  value = aws_lambda_function.webhook.function_name
}

output "idempotency_table_name" {
  description = "DynamoDB idempotency table (for webhook deduplication)."
  value       = aws_dynamodb_table.idempotency.name
}

output "idempotency_table_arn" {
  value = aws_dynamodb_table.idempotency.arn
}

output "stripe_secrets_arn" {
  description = "Pass-through of the caller-supplied Stripe Secrets Manager ARN."
  value       = var.stripe_secrets_arn
}
