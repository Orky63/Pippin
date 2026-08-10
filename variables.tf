variable "name" {
  description = "Short client identifier used in resource names (lowercase alphanumeric + hyphens)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens only."
  }
}

variable "domain_name" {
  description = "Apex domain (e.g. example.com)."
  type        = string
}

variable "aliases" {
  description = <<-EOT
    CloudFront distribution aliases (domain names).
    Required when dns_mode is self_managed or external.
    Ignored when dns_mode is none.
    Example: ["example.com", "www.example.com"]
  EOT
  type        = list(string)
  default     = []
}

variable "distribution_description" {
  description = <<-EOT
    Optional description for the CloudFront distribution (helpful for console identification).
    If empty, defaults to "{name}-cdn".
    Example: "Fort Wood Masjid Website CDN"
  EOT
  type        = string
  default     = ""
}

variable "dns_mode" {
  description = <<-EOT
    Controls DNS and certificate lifecycle.
      none          - CloudFront default cert, no aliases. Use during active development.
      self_managed  - Module creates Route53 zone + ACM cert with automatic DNS validation.
                      Outputs name_servers for client name-server cutover.
      external      - Client owns DNS. Provide a pre-validated certificate_arn.
                      Module attaches it to CloudFront with the given aliases.
  EOT
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "self_managed", "external"], var.dns_mode)
    error_message = "dns_mode must be none, self_managed, or external."
  }
}

variable "certificate_arn" {
  description = "Pre-validated ACM certificate ARN in us-east-1. Required when dns_mode is external."
  type        = string
  default     = null
}

variable "spa_mode" {
  description = "Return /index.html with HTTP 200 on 403/404 (single-page app routing)."
  type        = bool
  default     = false
}

variable "static_error_response_page_path" {
  description = "Optional CloudFront custom error page path for static sites, for example /404.html."
  type        = string
  default     = null

  validation {
    condition     = var.static_error_response_page_path == null || can(regex("^/.+", var.static_error_response_page_path))
    error_message = "static_error_response_page_path must start with '/'."
  }
}

variable "static_error_response_codes" {
  description = "Origin error codes that should render the static error page. Include 403 for private S3 origins, which return AccessDenied for missing objects."
  type        = list(number)
  default     = [403, 404]

  validation {
    condition     = alltrue([for code in var.static_error_response_codes : contains([400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504], code)])
    error_message = "static_error_response_codes can only include CloudFront-supported custom error response codes."
  }
}

variable "static_error_response_code" {
  description = "Viewer-facing HTTP status code returned with the static error page."
  type        = number
  default     = 404

  validation {
    condition     = contains([200, 400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504], var.static_error_response_code)
    error_message = "static_error_response_code must be a CloudFront-supported response code."
  }
}

variable "static_error_caching_min_ttl" {
  description = "Minimum CloudFront cache TTL, in seconds, for static error responses."
  type        = number
  default     = 60

  validation {
    condition     = var.static_error_caching_min_ttl >= 0
    error_message = "static_error_caching_min_ttl must be greater than or equal to 0."
  }
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "is_ipv6_enabled" {
  description = "Whether IPv6 is enabled for the CloudFront distribution."
  type        = bool
  default     = true
}

variable "enable_site_password" {
  description = "Protect static site content with HTTP Basic Auth via CloudFront Functions. Does not affect API routes."
  type        = bool
  default     = false
}

variable "site_password" {
  description = "Password for HTTP Basic Auth. Required when enable_site_password is true. Store as a sensitive variable in TFC."
  type        = string
  default     = null
  sensitive   = true
}

variable "site_password_username" {
  description = "Username for HTTP Basic Auth."
  type        = string
  default     = "admin"
}

variable "enable_clean_urls" {
  description = <<-EOT
    Rewrite requests at the edge so the site can be served without .html
    extensions and with transparent subdirectory index resolution.

      /about       -> rewrite to /about.html (200)
      /admin/      -> rewrite to /admin/index.html (200)
      /foo.html    -> 301 to /foo (SEO-preserving canonicalisation)
      /foo/index.html -> 301 to /foo/
      /style.css, /main.js, /fonts/foo.woff2 -> unchanged (asset passthrough)

    Implemented as a CloudFront Function on viewer-request. Composes with
    enable_site_password: basic-auth runs first, then the rewrite.
  EOT
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Attach an existing WAF Web ACL to the distribution. Mutually exclusive with enable_core_protections."
  type        = bool
  default     = false
}

variable "waf_acl_arn" {
  description = "ARN of an existing WAF Web ACL (us-east-1, CLOUDFRONT scope). Required when enable_waf is true."
  type        = string
  default     = null
}

variable "enable_core_protections" {
  description = <<-EOT
    Enable AWS WAF core protections on the CloudFront distribution.
    Creates a managed WAF WebACL with AWS rule groups:
      - AWSManagedRulesAmazonIpReputationList (known-bad IPs)
      - AWSManagedRulesCommonRuleSet (OWASP Top 10)
      - AWSManagedRulesKnownBadInputsRuleSet (Log4j, bad inputs)
    Mutually exclusive with enable_waf.
  EOT
  type        = bool
  default     = false
}

variable "enable_contact_form" {
  description = "Provision contact form Lambda behind /api/contact on the CloudFront distribution."
  type        = bool
  default     = true
}

variable "contact_from_email" {
  description = "SES sender address. Required when enable_contact_form is true."
  type        = string
  default     = null
}

variable "contact_to_email" {
  description = "Contact form recipient address. Required when enable_contact_form is true."
  type        = string
  default     = null
}

variable "ses_identity_arn" {
  description = "ARN of the existing SES identity used to scope the ses:SendEmail IAM condition."
  type        = string
  default     = null
}

variable "enable_payments" {
  description = "Provision minimal Stripe payment + webhook Lambdas behind /api/stripe/* on CloudFront."
  type        = bool
  default     = false
}

variable "stripe_secrets_arn" {
  description = <<-EOT
    Pre-existing Secrets Manager secret ARN containing Stripe keys
    (at minimum `{ secret_key, webhook_secret }`). Required when
    enable_payments is true — the module does not provision the secret
    itself. Create and populate it out-of-band before applying.
  EOT
  type        = string
  default     = null
}

variable "payment_bundle_zip" {
  description = <<-EOT
    Path to a pre-built, esbuild-bundled zip for the Stripe payment Lambda.
    Required when enable_payments is true. Zip must contain a single-file
    index.mjs with a `handler` export and all dependencies tree-shaken and
    inlined (no node_modules). See the module README for the build contract.
  EOT
  type        = string
  default     = null
}

variable "webhook_bundle_zip" {
  description = <<-EOT
    Path to a pre-built, esbuild-bundled zip for the Stripe webhook Lambda.
    Required when enable_payments is true.
  EOT
  type        = string
  default     = null
}

variable "contact_bundle_zip" {
  description = <<-EOT
    Path to a pre-built zip for the contact Lambda. Required when
    enable_contact_form is true. Bundling is optional (the contact handler
    can rely on the runtime-bundled AWS SDK v3).
  EOT
  type        = string
  default     = null
}

variable "payment_extra_environment" {
  description = "Extra env vars merged onto the payment Lambda's default env."
  type        = map(string)
  default     = {}
}

variable "webhook_extra_environment" {
  description = "Extra env vars merged onto the webhook Lambda's default env."
  type        = map(string)
  default     = {}
}

variable "lambda_runtime" {
  description = "Node.js runtime for all Lambdas. Default tracks the current AWS-recommended managed runtime."
  type        = string
  default     = "nodejs24.x"
}

variable "lambda_architecture" {
  description = "CPU architecture for all Lambdas. arm64 is ~20%% cheaper and faster for most JS workloads."
  type        = string
  default     = "arm64"
  validation {
    condition     = contains(["arm64", "x86_64"], var.lambda_architecture)
    error_message = "lambda_architecture must be arm64 or x86_64."
  }
}

variable "api_throttle_burst" {
  description = "API Gateway stage burst throttle limit (concurrent requests)."
  type        = number
  default     = 100
}

variable "api_throttle_rate" {
  description = "API Gateway stage steady-state throttle limit (requests/sec)."
  type        = number
  default     = 50
}

variable "csp_additional" {
  description = "Extra CSP directives appended to the default policy (e.g. \"connect-src https://api.example.com\")."
  type        = string
  default     = ""
}

variable "csp_default_src" {
  description = "Sources for the default-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'self'"]
}

variable "csp_script_src" {
  description = "Sources for the script-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'self'", "'unsafe-inline'", "https://js.stripe.com"]
}

variable "csp_style_src" {
  description = "Sources for the style-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"]
}

variable "csp_img_src" {
  description = "Sources for the img-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'self'", "data:", "https:"]
}

variable "csp_font_src" {
  description = "Sources for the font-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'self'", "data:", "https:", "https://fonts.gstatic.com"]
}

variable "csp_connect_src" {
  description = "Sources for the connect-src CSP directive before csp_connect_src_additional is merged. Empty list omits the directive unless additional sources are set."
  type        = list(string)
  default     = ["'self'", "https://api.stripe.com"]
}

variable "csp_connect_src_additional" {
  description = "Extra origins to merge into the connect-src CSP directive (e.g. Cognito, API Gateway)."
  type        = list(string)
  default     = []
}

variable "csp_directive_order" {
  description = "Ordered CSP directive names used when serializing the Content-Security-Policy header."
  type        = list(string)
  default     = ["default-src", "script-src", "style-src", "img-src", "font-src", "connect-src", "media-src", "frame-src", "frame-ancestors", "object-src", "base-uri", "form-action"]

  validation {
    condition = alltrue([
      for directive in var.csp_directive_order :
      contains(["default-src", "script-src", "style-src", "img-src", "font-src", "connect-src", "media-src", "frame-src", "frame-ancestors", "object-src", "base-uri", "form-action"], directive)
    ])
    error_message = "csp_directive_order can only include supported CSP directive names."
  }
}

variable "csp_media_src" {
  description = "Sources for the media-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = []
}

variable "csp_frame_src" {
  description = "Sources for the frame-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = []
}

variable "csp_frame_ancestors" {
  description = "Sources for the frame-ancestors CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'none'"]
}

variable "csp_object_src" {
  description = "Sources for the object-src CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = []
}

variable "csp_base_uri" {
  description = "Sources for the base-uri CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'self'"]
}

variable "csp_form_action" {
  description = "Sources for the form-action CSP directive. Empty list omits the directive."
  type        = list(string)
  default     = ["'self'"]
}

variable "permissions_policy" {
  description = "Optional Permissions-Policy response header value."
  type        = string
  default     = ""
}

variable "enable_github_oidc" {
  description = <<-EOT
    Create a per-website GitHub Actions deploy role with least-privilege access.
    Requires github_org and github_repo to be set.
    Assumes the GitHub OIDC provider already exists at the AWS account level
    (one-time bootstrap — see README "Account Bootstrap" section).
  EOT
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organization or user. Required when enable_github_oidc is true."
  type        = string
  default     = null
}

variable "github_repo" {
  description = "GitHub repository name. Required when enable_github_oidc is true."
  type        = string
  default     = null
}

variable "github_branch" {
  description = <<-EOT
    Git branch allowed to assume the deploy role.
    "main" - only main branch (recommended for production)
    "*"    - any branch/PR/tag (use only for dev/staging)
  EOT
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Tags merged onto every resource."
  type        = map(string)
  default     = {}
}
