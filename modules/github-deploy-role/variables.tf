variable "name" {
  description = "Client identifier (used in role name)."
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user (e.g. \"rotordev\")."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. \"client-website\")."
  type        = string
}

variable "github_branch" {
  description = <<-EOT
    Git ref pattern allowed to assume the role.
    "main"   - Only main branch can deploy (recommended for production)
    "*"      - Any branch/PR/tag can deploy (use only for dev/staging)
    "<name>" - Specific branch only (e.g. "production")
  EOT
  type        = string
  default     = "main"
}

variable "bucket_arn" {
  description = "S3 bucket ARN that this role can sync content to."
  type        = string
}

variable "distribution_arn" {
  description = "CloudFront distribution ARN that this role can invalidate."
  type        = string
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
