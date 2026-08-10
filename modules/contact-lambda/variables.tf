variable "name" {
  description = "Client identifier."
  type        = string
}

variable "api_id" {
  description = "ID of the shared aws_apigatewayv2_api this module attaches its route to."
  type        = string
}

variable "api_execution_arn" {
  description = "execution_arn of the shared aws_apigatewayv2_api (used to scope the lambda invoke permission)."
  type        = string
}

variable "from_email" {
  description = "SES sender email address."
  type        = string
}

variable "to_email" {
  description = "Contact form recipient email address."
  type        = string
}

variable "ses_identity_arn" {
  description = "ARN of the SES identity to scope the SendEmail IAM condition."
  type        = string
  default     = null
}

variable "bundle_zip" {
  description = <<-EOT
    Path to a pre-built, esbuild-bundled zip for the contact Lambda.
    Must contain a single-file `index.mjs` with a `handler` export. Because
    the contact handler only uses the runtime-bundled AWS SDK v3, you can
    also pass a plain zip of index.mjs — bundling is optional here, required
    only if you add third-party dependencies.

    See the module README for the handler contract.
  EOT
  type        = string
}

variable "runtime" {
  description = "Lambda Node.js runtime."
  type        = string
  default     = "nodejs24.x"
}

variable "architecture" {
  description = "Lambda CPU architecture."
  type        = string
  default     = "arm64"
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "reserved_concurrent_executions" {
  description = "Per-function reserved concurrency. -1 disables the reservation."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
