terraform {
  required_version = ">= 1.14.0"
  cloud {
    organization = "rotordev-ops"
    workspaces {
      name = "example-with-payments"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "example-payments"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Example with Stripe payments integration
module "website" {
  source = "../.."

  name                     = "example-payments"
  domain_name              = "example.com"
  aliases                  = ["example.com", "www.example.com"]
  dns_mode                 = "self_managed"
  distribution_description = "Example Website CDN"

  enable_contact_form = true
  contact_from_email  = "noreply@example.com"
  contact_to_email    = "admin@example.com"
  ses_identity_arn    = "arn:aws:ses:us-east-1:123456789012:identity/example.com"
  contact_bundle_zip  = "${path.root}/build/contact.zip"

  enable_payments    = true
  stripe_secrets_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:stripe-keys-XXXXX"
  payment_bundle_zip = "${path.root}/build/payment.zip"
  webhook_bundle_zip = "${path.root}/build/webhook.zip"

  # Add Stripe domains to CSP
  csp_additional = "connect-src https://api.stripe.com"

  # Per-website GitHub Actions deploy role
  enable_github_oidc = true
  github_org         = "myorg"
  github_repo        = "example-payments-site"
  github_branch      = "main"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "github_actions_role_arn" {
  value = module.website.github_actions_role_arn
}

output "bucket_name" {
  value = module.website.bucket_name
}

output "distribution_id" {
  value = module.website.distribution_id
}

output "website_url" {
  value = module.website.website_url
}

output "name_servers" {
  value = module.website.name_servers
}

output "payment_api_endpoint" {
  description = "Stripe payment intent endpoint."
  value       = "${module.website.website_url}${module.website.payment_api_path}"
}
