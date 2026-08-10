terraform {
  required_version = ">= 1.14.0"
  cloud {
    organization = "rotordev-ops"
    workspaces {
      name = "example-minimal"
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
      Project     = "example-minimal"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Minimal example: S3 + CloudFront with default cert (development)
module "website" {
  source = "../.."

  name        = "example-minimal"
  domain_name = "example.com"
  dns_mode    = "none"

  enable_contact_form = false
  enable_payments     = false

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "bucket_name" {
  description = "S3 bucket for website content."
  value       = module.website.bucket_name
}

output "distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.website.distribution_id
}

output "website_url" {
  description = "Temporary CloudFront URL (use for development)."
  value       = module.website.website_url
}
