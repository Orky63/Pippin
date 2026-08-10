variable "name" {
  description = "Client identifier."
  type        = string
}

variable "domain_name" {
  description = "Apex domain."
  type        = string
}

variable "aliases" {
  description = "List of domain aliases for CloudFront."
  type        = list(string)
  default     = []
}

variable "dns_mode" {
  description = "DNS management mode: none | self_managed | external."
  type        = string
  default     = "none"
}

variable "certificate_arn" {
  description = "Pre-validated ACM cert ARN in us-east-1. Used when dns_mode is external."
  type        = string
  default     = null
}

variable "csp_additional" {
  description = "Additional CSP directives appended to defaults."
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
  description = "Extra origins merged into the connect-src CSP directive alongside the module defaults ('self', https://api.stripe.com)."
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

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default     = {}
}
