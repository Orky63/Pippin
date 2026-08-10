# Removed: lambda OAC is no longer used. Allow old deployments to clean it from state.
removed {
  from = aws_cloudfront_origin_access_control.lambda
  lifecycle { destroy = false }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = var.is_ipv6_enabled
  http_version        = "http2and3"
  price_class         = var.price_class
  default_root_object = "index.html"
  comment             = local.distribution_description
  aliases             = var.dns_mode != "none" ? var.aliases : []
  web_acl_id          = var.enable_core_protections ? aws_wafv2_web_acl.core[0].arn : (var.enable_waf ? var.waf_acl_arn : null)
  tags                = local.tags

  # Validation: trigger if aliases missing for production modes
  lifecycle {
    precondition {
      condition     = var.dns_mode == "none" || length(var.aliases) > 0
      error_message = "ERROR: aliases must be provided when dns_mode is '${var.dns_mode}'. Example: [\"example.com\", \"www.example.com\"]"
    }
  }

  # --- Origins ---

  origin {
    domain_name              = module.site.bucket_regional_domain_name
    origin_id                = "${var.name}-s3"
    origin_access_control_id = module.site.s3_oac_id
  }

  # Single API Gateway HTTP API origin. Each lambda has its own security:
  # - payment intent: secured by Stripe auth (client confirms payment)
  # - webhook: secured by Stripe signature verification
  # - contact: secured by rate limiting on the stage
  dynamic "origin" {
    for_each = local.api_needed ? [1] : []
    content {
      domain_name = local.api_domain
      origin_id   = "${var.name}-api"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # --- Default behavior: S3 static site ---

  default_cache_behavior {
    target_origin_id       = "${var.name}-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    # Managed-CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    # Managed-CORS-S3Origin
    origin_request_policy_id   = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
    response_headers_policy_id = module.site.response_headers_policy_id

    # Composed viewer-request function: basic auth and/or clean-URL rewrites.
    # Only attached when at least one feature is enabled.
    dynamic "function_association" {
      for_each = local.viewer_request_needed ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.viewer_request[0].arn
      }
    }
  }

  # --- Ordered behaviors: API routes ---
  #
  # All three API routes share the same origin (the HTTP API). Each path
  # pattern exists so we can lock down which paths are reachable through
  # CloudFront — the API itself only has routes the modules define, but
  # explicit behaviors document the surface area and let us evolve cache
  # policy per route if needed.

  dynamic "ordered_cache_behavior" {
    for_each = var.enable_contact_form ? [1] : []
    content {
      path_pattern           = "/api/contact"
      target_origin_id       = "${var.name}-api"
      viewer_protocol_policy = "https-only"
      compress               = false
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD"]

      # Managed-CachingDisabled
      cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      # Managed-AllViewerExceptHostHeader
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.enable_payments ? [1] : []
    content {
      path_pattern           = "/api/stripe/intent"
      target_origin_id       = "${var.name}-api"
      viewer_protocol_policy = "https-only"
      compress               = false
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD"]

      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.enable_payments ? [1] : []
    content {
      path_pattern           = "/api/stripe/webhook"
      target_origin_id       = "${var.name}-api"
      viewer_protocol_policy = "https-only"
      compress               = false
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD"]

      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    }
  }

  # --- Custom error responses ---

  dynamic "custom_error_response" {
    for_each = local.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  # --- Viewer cert: in-place update when dns_mode changes ---

  viewer_certificate {
    cloudfront_default_certificate = var.dns_mode == "none" ? true : null
    acm_certificate_arn            = var.dns_mode != "none" ? module.site.certificate_arn : null
    ssl_support_method             = var.dns_mode != "none" ? "sni-only" : null
    minimum_protocol_version       = var.dns_mode != "none" ? "TLSv1.2_2021" : null
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  depends_on = [module.site]
}

# S3 bucket policy: scoped to this specific distribution ARN
data "aws_iam_policy_document" "s3_cf" {
  statement {
    sid     = "AllowCloudFrontServicePrincipal"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${module.site.bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = module.site.bucket_name
  policy = data.aws_iam_policy_document.s3_cf.json
}
