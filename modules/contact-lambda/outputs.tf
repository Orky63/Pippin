output "function_arn" {
  value = aws_lambda_function.contact.arn
}

output "function_name" {
  value = aws_lambda_function.contact.function_name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.contact.name
}
