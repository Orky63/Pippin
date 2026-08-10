terraform {
  required_version = ">= 1.14.0"
  cloud {
    organization = "rotordev-ops"
    workspaces {
      name = "example-with-contact"
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
      Project     = "example-with-contact"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Example with self-managed DNS and contact form
module "website" {
  source = "../.."

  name                     = "example-contact"
  domain_name              = "example.com"
  aliases                  = ["example.com", "www.example.com"]
  dns_mode                 = "self_managed"
  distribution_description = "Example Website CDN"

  enable_contact_form = true
  contact_from_email  = "noreply@example.com"
  contact_to_email    = "admin@example.com"
  ses_identity_arn    = "arn:aws:ses:us-east-1:123456789012:identity/example.com"
  contact_bundle_zip  = "${path.root}/../../modules/contact-lambda/src/dist/contact.zip"

  enable_payments = false

  # Per-website GitHub Actions deploy role (least-privilege)
  enable_github_oidc = true
  github_org         = "myorg"
  github_repo        = "example-website"
  github_branch      = "main"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN secret in your GitHub repo."
  value       = module.website.github_actions_role_arn
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
  description = "Route53 NS records for client name-server cutover."
  value       = module.website.name_servers
}
