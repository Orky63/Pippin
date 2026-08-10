# CloudFront response headers policy with security headers + configurable CSP
locals {
  csp_directives = {
    "default-src"     = length(var.csp_default_src) > 0 ? "default-src ${join(" ", var.csp_default_src)}" : ""
    "script-src"      = length(var.csp_script_src) > 0 ? "script-src ${join(" ", var.csp_script_src)}" : ""
    "style-src"       = length(var.csp_style_src) > 0 ? "style-src ${join(" ", var.csp_style_src)}" : ""
    "img-src"         = length(var.csp_img_src) > 0 ? "img-src ${join(" ", var.csp_img_src)}" : ""
    "font-src"        = length(var.csp_font_src) > 0 ? "font-src ${join(" ", var.csp_font_src)}" : ""
    "connect-src"     = length(concat(var.csp_connect_src, var.csp_connect_src_additional)) > 0 ? "connect-src ${join(" ", concat(var.csp_connect_src, var.csp_connect_src_additional))}" : ""
    "media-src"       = length(var.csp_media_src) > 0 ? "media-src ${join(" ", var.csp_media_src)}" : ""
    "frame-src"       = length(var.csp_frame_src) > 0 ? "frame-src ${join(" ", var.csp_frame_src)}" : ""
    "frame-ancestors" = length(var.csp_frame_ancestors) > 0 ? "frame-ancestors ${join(" ", var.csp_frame_ancestors)}" : ""
    "object-src"      = length(var.csp_object_src) > 0 ? "object-src ${join(" ", var.csp_object_src)}" : ""
    "base-uri"        = length(var.csp_base_uri) > 0 ? "base-uri ${join(" ", var.csp_base_uri)}" : ""
    "form-action"     = length(var.csp_form_action) > 0 ? "form-action ${join(" ", var.csp_form_action)}" : ""
  }
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${var.name}-security-headers"
  comment = "Security headers for ${var.name} static site"

  security_headers_config {
    # HSTS: 1 year with preload + includeSubdomains
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }

    # X-Content-Type-Options: nosniff
    content_type_options {
      override = true
    }

    # X-Frame-Options: DENY
    frame_options {
      frame_option = "DENY"
      override     = true
    }

    # Referrer-Policy: strict-origin-when-cross-origin
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    # X-XSS-Protection: 1; mode=block (legacy, but good for older browsers)
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }

    # Content-Security-Policy: custom (with optional additional directives)
    content_security_policy {
      content_security_policy = join("; ", compact(concat(
        [for directive in var.csp_directive_order : lookup(local.csp_directives, directive, "")],
        var.csp_additional != "" ? [var.csp_additional] : []
      )))
      override = true
    }
  }

  dynamic "custom_headers_config" {
    for_each = var.permissions_policy != "" ? [var.permissions_policy] : []
    content {
      items {
        header   = "Permissions-Policy"
        override = true
        value    = custom_headers_config.value
      }
    }
  }
}
