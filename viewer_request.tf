locals {
  viewer_request_needed = var.enable_site_password || var.enable_clean_urls
}

# Rename: basic-auth-only function is now a composable viewer-request handler
# (auth + clean URLs). Preserve state for existing consumers.
moved {
  from = aws_cloudfront_function.basic_auth
  to   = aws_cloudfront_function.viewer_request
}

resource "aws_cloudfront_function" "viewer_request" {
  count = local.viewer_request_needed ? 1 : 0

  name    = "${var.name}-viewer-request"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Viewer-request handler (auth + clean URLs) for ${var.name}"

  code = templatefile("${path.module}/functions/viewer-request.js.tftpl", {
    enable_site_password = var.enable_site_password
    enable_clean_urls    = var.enable_clean_urls
    credentials_base64 = var.enable_site_password ? base64encode(
      "${var.site_password_username}:${var.site_password}"
    ) : ""
  })

  # name is ForceNew on aws_cloudfront_function. When consumers upgrade from
  # the old basic-auth-only module version, the rename triggers a replace —
  # create the new function first so the distribution can swap ARNs without
  # an auth-gate gap during apply.
  lifecycle {
    create_before_destroy = true
  }
}

# v6.3.0 shipped a viewer-response fallback that was a no-op: CloudFront
# Functions forbid viewer-response from setting a 3xx status, so the 301
# was silently dropped. Remove the resource cleanly on upgrade.
removed {
  from = aws_cloudfront_function.viewer_response
  lifecycle { destroy = true }
}
