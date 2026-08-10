variable "name" {
  description = "Client identifier."
  type        = string
}

variable "api_id" {
  description = "ID of the shared aws_apigatewayv2_api this module attaches routes to."
  type        = string
}

variable "api_execution_arn" {
  description = "execution_arn of the shared aws_apigatewayv2_api (used to scope lambda invoke permissions)."
  type        = string
}

variable "stripe_secrets_arn" {
  description = "Secrets Manager ARN containing Stripe keys (secret_key, webhook_secret)."
  type        = string
}

variable "payment_bundle_zip" {
  description = <<-EOT
    Path to a pre-built, esbuild-bundled zip for the Stripe payment Lambda.
    The zip must contain a single-file `index.mjs` with a `handler` export,
    all dependencies tree-shaken and inlined (no node_modules inside the zip).

    Build contract (example, using pnpm + esbuild):
      esbuild index.mjs --bundle --platform=node --target=node24 \
        --format=esm --outfile=dist/index.mjs
      cd dist && zip -r payment.zip .

    See the module README for the full handler contract (request shape,
    env vars, response shape).
  EOT
  type        = string
}

variable "webhook_bundle_zip" {
  description = <<-EOT
    Path to a pre-built, esbuild-bundled zip for the Stripe webhook Lambda.
    Same contract as payment_bundle_zip: single-file handler with all
    dependencies inlined, no node_modules.
  EOT
  type        = string
}

variable "runtime" {
  description = "Lambda Node.js runtime. Default tracks the current AWS-recommended managed runtime."
  type        = string
  default     = "nodejs24.x"
}

variable "architecture" {
  description = "Lambda CPU architecture. arm64 is ~20% cheaper and faster for most JS workloads."
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
  default     = 10
}

variable "payment_extra_environment" {
  description = <<-EOT
    Extra environment variables merged onto the payment Lambda's default env
    (STRIPE_SECRETS_ARN). Use for caller-specific config like an orders table
    name, feature flags, etc.
  EOT
  type        = map(string)
  default     = {}
}

variable "webhook_extra_environment" {
  description = <<-EOT
    Extra environment variables merged onto the webhook Lambda's default env
    (STRIPE_SECRETS_ARN, IDEMPOTENCY_TABLE). Use for caller-specific config
    like an orders table name, fanout topic ARN, etc.
  EOT
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
