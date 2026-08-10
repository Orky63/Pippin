module "site" {
  source = "./modules/website-foundations"

  name                       = var.name
  domain_name                = var.domain_name
  aliases                    = var.aliases
  dns_mode                   = var.dns_mode
  certificate_arn            = var.certificate_arn
  csp_additional             = var.csp_additional
  csp_base_uri               = var.csp_base_uri
  csp_connect_src_additional = var.csp_connect_src_additional
  csp_connect_src            = var.csp_connect_src
  csp_default_src            = var.csp_default_src
  csp_directive_order        = var.csp_directive_order
  csp_font_src               = var.csp_font_src
  csp_form_action            = var.csp_form_action
  csp_frame_ancestors        = var.csp_frame_ancestors
  csp_frame_src              = var.csp_frame_src
  csp_img_src                = var.csp_img_src
  csp_media_src              = var.csp_media_src
  csp_object_src             = var.csp_object_src
  csp_script_src             = var.csp_script_src
  csp_style_src              = var.csp_style_src
  permissions_policy         = var.permissions_policy
  tags                       = local.tags

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

module "contact" {
  count  = var.enable_contact_form ? 1 : 0
  source = "./modules/contact-lambda"

  name              = var.name
  api_id            = aws_apigatewayv2_api.this[0].id
  api_execution_arn = aws_apigatewayv2_api.this[0].execution_arn
  from_email        = var.contact_from_email
  to_email          = var.contact_to_email
  ses_identity_arn  = var.ses_identity_arn
  bundle_zip        = var.contact_bundle_zip
  runtime           = var.lambda_runtime
  architecture      = var.lambda_architecture
  tags              = local.tags
}

module "payments" {
  count  = var.enable_payments ? 1 : 0
  source = "./modules/payment-lambda"

  name                      = var.name
  api_id                    = aws_apigatewayv2_api.this[0].id
  api_execution_arn         = aws_apigatewayv2_api.this[0].execution_arn
  stripe_secrets_arn        = var.stripe_secrets_arn
  payment_bundle_zip        = var.payment_bundle_zip
  webhook_bundle_zip        = var.webhook_bundle_zip
  payment_extra_environment = var.payment_extra_environment
  webhook_extra_environment = var.webhook_extra_environment
  runtime                   = var.lambda_runtime
  architecture              = var.lambda_architecture
  tags                      = local.tags
}

module "github_oidc" {
  count  = var.enable_github_oidc ? 1 : 0
  source = "./modules/github-deploy-role"

  name             = var.name
  github_org       = var.github_org
  github_repo      = var.github_repo
  github_branch    = var.github_branch
  bucket_arn       = module.site.bucket_arn
  distribution_arn = aws_cloudfront_distribution.this.arn
  tags             = local.tags
}

# Validate github_oidc inputs
check "github_oidc_inputs" {
  assert {
    condition     = !var.enable_github_oidc || (var.github_org != null && var.github_repo != null)
    error_message = "github_org and github_repo must be set when enable_github_oidc is true."
  }
}

# Validate payments inputs
check "payments_inputs" {
  assert {
    condition     = !var.enable_payments || var.stripe_secrets_arn != null
    error_message = "stripe_secrets_arn must be set when enable_payments is true. Create the Secrets Manager secret out-of-band and pass its ARN."
  }
  assert {
    condition     = !var.enable_payments || (var.payment_bundle_zip != null && var.webhook_bundle_zip != null)
    error_message = "payment_bundle_zip and webhook_bundle_zip must both be set when enable_payments is true. Build them with esbuild — see the README."
  }
}

# Validate contact form inputs
check "contact_form_inputs" {
  assert {
    condition     = !var.enable_contact_form || var.contact_bundle_zip != null
    error_message = "contact_bundle_zip must be set when enable_contact_form is true."
  }
}

# Validate site password inputs
check "site_password_inputs" {
  assert {
    condition     = !var.enable_site_password || (var.site_password != null && var.site_password != "")
    error_message = "site_password must be set (non-empty) when enable_site_password is true."
  }
}

# Validate WAF mutual exclusion
check "waf_mutual_exclusion" {
  assert {
    condition     = !(var.enable_core_protections && var.enable_waf)
    error_message = "enable_core_protections and enable_waf are mutually exclusive. Use enable_core_protections for managed rules, or enable_waf with waf_acl_arn for a custom ACL."
  }
}

# Validate WAF ACL ARN when custom WAF is enabled
check "waf_acl_arn_required" {
  assert {
    condition     = !var.enable_waf || var.waf_acl_arn != null
    error_message = "waf_acl_arn must be set when enable_waf is true."
  }
}
