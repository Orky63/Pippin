output "role_arn" {
  description = "GitHub Actions deploy role ARN. Set this as the AWS_ROLE_ARN secret in your GitHub repo."
  value       = aws_iam_role.deploy.arn
}

output "role_name" {
  description = "GitHub Actions deploy role name."
  value       = aws_iam_role.deploy.name
}
