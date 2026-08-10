# Look up the existing GitHub OIDC provider in the AWS account.
# This must be created once per account (see README "Account Bootstrap" section).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Trust policy: allow GitHub Actions from a specific repo (optionally scoped to a branch)
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # Audience must match the configured value in GitHub Actions
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Repo + branch scoping
    condition {
      test     = var.github_branch == "*" ? "StringLike" : "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        var.github_branch == "*"
        ? "repo:${var.github_org}/${var.github_repo}:*"
        : "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name        = "${var.name}-github-deploy"
  description = "GitHub Actions deploy role for ${var.github_org}/${var.github_repo}"

  assume_role_policy = data.aws_iam_policy_document.assume.json

  # Limit session duration (default is 1 hour, max is 12)
  max_session_duration = 3600

  tags = var.tags
}

# Least-privilege deploy policy: only S3 sync + CloudFront invalidation
data "aws_iam_policy_document" "deploy" {
  statement {
    sid    = "S3ListAndLocation"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [var.bucket_arn]
  }

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.bucket_arn}/*"]
  }

  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]
    resources = [var.distribution_arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
