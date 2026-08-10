# rd-website-module

Reusable Terraform module for static websites on AWS. Provisions S3 + CloudFront + ACM + Route53 + Lambda contact form + optional Stripe payments.

**Features:**
- ✅ S3 private origin with OAC (no public access)
- ✅ API Gateway HTTP API backend (single origin) with stage-level throttling
- ✅ CloudFront distribution with HTTP/2+3, IPv6, modern TLS
- ✅ ACM certificates (automatic validation in Route53 or bring-your-own)
- ✅ Route53 hosted zone management (optional)
- ✅ Contact form Lambda + SES integration
- ✅ Optional Stripe payment + webhook handlers
- ✅ Security headers (HSTS, CSP, X-Frame-Options, etc.)
- ✅ IAM least-privilege by default
- ✅ Node.js 24.x (arm64) Lambdas for cost & performance (overridable)
- ✅ Terraform Cloud integration ready

## Quick Start

> **Deploy strategy:** Start with **local state** for fast iteration, verify everything works, then **migrate state to Terraform Cloud** before wiring up CI/CD. This avoids the chicken-and-egg where the CI/CD pipeline tries to read outputs from an empty TFC workspace.

### Phase 1 — Local Bootstrap

1. Create a client repo:
   ```bash
   mkdir my-website && cd my-website
   git init && git remote add origin https://github.com/myorg/my-website.git
   ```

2. Copy `examples/with-contact/main.tf` and customize. **Do NOT include the `cloud {}` block yet** — use local state first:
   ```hcl
   terraform {
     required_version = ">= 1.14.0"
     # NOTE: cloud {} block added in Phase 2 — start with local state
   }

   provider "aws" {
     region = "us-east-1"
     default_tags { tags = { Project = "my-website" } }
   }

   provider "aws" { alias = "us_east_1", region = "us-east-1" }

   module "website" {
     source = "git::https://github.com/rotordev-ops/rd-website-module.git?ref=v1.0.0"

     name        = "mysite"
     domain_name = "mysite.com"
     aliases     = ["mysite.com", "www.mysite.com"]
     dns_mode    = "self_managed"

     enable_contact_form = true
     contact_from_email  = "noreply@mysite.com"
     contact_to_email    = "admin@mysite.com"
     ses_identity_arn    = "arn:aws:ses:us-east-1:123456789012:identity/mysite.com"

     enable_github_oidc = true
     github_org         = "myorg"
     github_repo        = "my-website"

     providers = {
       aws           = aws
       aws.us_east_1 = aws.us_east_1
     }
   }

   output "github_actions_role_arn" { value = module.website.github_actions_role_arn }
   output "bucket_name"             { value = module.website.bucket_name }
   output "distribution_id"         { value = module.website.distribution_id }
   ```

3. Copy website template:
   ```bash
   cp -r path/to/rd-website-module/examples/website/* .
   ```

4. Apply Terraform locally:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
   At this point, your S3 bucket, CloudFront distribution, Route53 zone, and Lambdas exist. State is in `terraform.tfstate` on your machine.

5. (For `self_managed` DNS) Update the client's name servers to the Route53 NS records shown in output.

6. Verify the infra is healthy — visit the CloudFront URL, test the contact form, etc.

---

### Phase 2 — Migrate State to Terraform Cloud

> ⚠️ **This step is required before CI/CD will work.** The deploy workflow fetches outputs from TFC, so the state must live there.

1. Create a Terraform Cloud workspace:
   - Go to [app.terraform.io](https://app.terraform.io) → your org → **New workspace**
   - Choose **CLI-Driven Workflow** (not VCS-driven — we want `terraform apply` to still work locally, TFC just stores state)
   - Name it (e.g. `my-website-prod`)
   - After creation: **Settings → General → Execution Mode → Local** (keeps apply on your machine, TFC only stores state)

2. Add the `cloud {}` block to your `main.tf`:
   ```hcl
   terraform {
     required_version = ">= 1.14.0"
     cloud {
       organization = "your-org"
       workspaces { name = "my-website-prod" }
     }
   }
   ```

3. Log in to Terraform Cloud from your terminal (one-time per machine):
   ```bash
   terraform login
   ```

4. Re-initialize — **Terraform will prompt to migrate existing state to the new backend**:
   ```bash
   terraform init
   ```
   ```
   Do you want to copy existing state to the new backend?
   ...
   Enter a value: yes
   ```
   Your local state is now uploaded to TFC. You can delete `terraform.tfstate` and `terraform.tfstate.backup` locally — TFC owns it now.

5. Verify state landed in TFC:
   ```bash
   terraform state list   # should list all resources, fetched from TFC
   ```
   Also check the TFC UI — workspace should show the current state version and outputs.

6. Run a no-op plan to confirm everything still reconciles:
   ```bash
   terraform plan
   # Should say: "No changes. Your infrastructure matches the configuration."
   ```

---

### Phase 3 — Wire Up CI/CD

1. Install pre-commit hooks in the child repo:
   ```bash
   cp path/to/rd-website-module/.pre-commit-config.yaml .
   pre-commit install
   ```
   Now `terraform fmt`, `tflint`, and `trivy` run automatically before each commit.

2. Copy the deploy workflow template:
   ```bash
   mkdir -p .github/workflows
   cp path/to/rd-website-module/.github/workflows/deploy-website.yml.tpl .github/workflows/deploy-website.yml
   ```
   Edit the `paths` section at the top of the file to match the website files in your repo.

3. Configure GitHub Action **secrets** (repo Settings → Secrets and variables → Actions → Secrets):
   - `AWS_ROLE_ARN` — get from `terraform output github_actions_role_arn`
   - `TF_API_TOKEN` — create a user API token at [app.terraform.io/app/settings/tokens](https://app.terraform.io/app/settings/tokens) (or a team token scoped to your workspace)
   - `STRIPE_PUBLISHABLE_KEY` — only if `enable_payments = true`

4. Configure GitHub Action **variables** (repo Settings → Secrets and variables → Actions → Variables):
   - `TF_WORKSPACE_ID` — **must be the workspace ID** (format: `ws-xxxxxxxxxx`), not the workspace name. Find it in TFC: **Workspace → Settings → General → Workspace ID**.

5. Push to `main`:
   ```bash
   git add .
   git commit -m "Initial deploy"
   git push -u origin main
   ```
   GitHub Actions will trigger, fetch outputs from TFC, sync files to S3, and invalidate CloudFront.

---

### Why This Order Matters

| Mistake | What Breaks |
|---------|-------------|
| Starting with `cloud {}` block before TFC workspace exists | `terraform init` fails — workspace doesn't exist yet |
| Apply locally, push to GitHub, skip state migration | CI/CD fetches empty outputs from TFC → `s3://null/` → AccessDenied |
| Using workspace **name** for `TF_WORKSPACE_ID` variable | API 404 → empty outputs → same `s3://null/` failure |
| Omitting `enable_github_oidc = true` | No deploy role → CI/CD can't auth to AWS |

---

## Architecture

```
Client Browser
      ↓
CloudFront (HTTPS, HTTP/2+3, IPv6)
      ├─ S3 origin (private, OAC)
      └─ API Gateway HTTP API origin
            ├─ POST /api/contact          → contact Lambda (rate-limited)
            ├─ POST /api/stripe/intent    → payment Lambda (Stripe auth)
            └─ POST /api/stripe/webhook   → webhook Lambda (Stripe signature)
      ↓
Route53 (optional)
```

**Why this shape:**
- One API Gateway HTTP API fronts every backend Lambda. One origin, one
  throttle budget (DDoS protection) — each Lambda owns its own integration,
  route, IAM role, and invoke permission inside its submodule.
- Each endpoint has its own security:
  - **Contact form:** rate-limited at the API stage level
  - **Payment intent:** secured by Stripe — the client must complete payment auth with Stripe
  - **Webhook:** secured by Stripe signature verification (cryptographic, not shared secret)
- No origin lockdown needed. The API Gateway URL is public, but calling it
  directly provides no advantage — legitimate use requires a valid Stripe
  account and confirmation. Rate limiting prevents cost blowup.

All resources tagged, encrypted by default, logs retained 14 days, IAM least-privilege.

---

## DNS & Certificate Lifecycle

### `dns_mode = "none"` (Development)
- CloudFront default certificate
- No aliases (uses `*.cloudfront.net` domain)
- No Route53 zone
- `aliases = []` — not validated
- Use for building & testing before going live

### `dns_mode = "self_managed"` (Production)
- ⚠️ **Required:** Populate `aliases` (e.g. `["example.com", "www.example.com"]`)
- Module creates Route53 hosted zone
- Module creates ACM cert in us-east-1 for all aliases
- Module auto-validates cert via Route53 CNAME records
- Module creates A/AAAA alias records to CloudFront
- Output: NS records for client name-server cutover
- Optional: `distribution_description` for console clarity

### `dns_mode = "external"` (Client-Hosted DNS)
- ⚠️ **Required:** Populate `aliases` (must match cert SANs)
- Client owns the domain and DNS provider
- You provide a pre-validated `certificate_arn`
- Module attaches cert to CloudFront with aliases
- Module outputs ACM validation CNAME records (for reference)

**Development → Production Workflow:**
```hcl
# Phase 1: Development (dns_mode = "none")
module "website" {
  source = "git::https://github.com/rotordev-ops/rd-website-module.git?ref=v1.0.0"
  
  name        = "mysite"
  domain_name = "mysite.com"
  dns_mode    = "none"  # Uses *.cloudfront.net
  aliases     = []      # Not needed yet
  
  # ... rest of config
}

# Phase 2: Production (dns_mode = "self_managed")
module "website" {
  source = "git::https://github.com/rotordev-ops/rd-website-module.git?ref=v1.0.0"
  
  name                      = "mysite"
  domain_name               = "mysite.com"
  dns_mode                  = "self_managed"  # ← flip this
  aliases                   = ["mysite.com", "www.mysite.com"]  # ← add this
  distribution_description = "My Site Website CDN"  # ← add for clarity
  
  # ... rest of config
}
# Then: terraform plan && terraform apply
# Terraform updates CF in-place with cert + aliases (no downtime)
# Output: NS records → give to client for name-server cutover
```

---

## Alternate Domain Names (Aliases) — Critical for Production

**Industry Standard:**
- Always include both apex domain (`example.com`) and www variant (`www.example.com`)
- Users expect both to work seamlessly
- Without aliases, only one domain (or neither with default cert) is accessible
- **This is non-negotiable for live production sites**

**Pattern:**
```hcl
# ✅ Correct for production
aliases = ["mysite.com", "www.mysite.com"]

# ❌ Incomplete
aliases = ["mysite.com"]  # www.mysite.com fails to resolve

# ✅ Also valid (legacy domains, regional variants)
aliases = ["mysite.com", "www.mysite.com", "legacy-domain.com", "ca.mysite.com"]
```

**When to Add:**
- `dns_mode = "none"`: Not needed (testing only, using CF default domain)
- `dns_mode = "self_managed"` or `"external"`: **Required before cert validation**
  - Module will error if you forget: `"aliases must be provided when dns_mode is 'self_managed'"`

---

## Distribution Description

Add a human-readable description to identify your distribution in the AWS console (useful if you manage many distributions in one account).

```hcl
distribution_description = "Fort Wood Masjid Website CDN"
# Or leave empty to auto-generate "{name}-cdn"
```

---

## SES Setup

The module does **not** manage SES domain identity, DKIM, SPF, or DMARC. You must:

1. Create an SES verified identity (email or domain) in AWS Console or via Terraform outside this module
2. Generate DKIM records (AWS provides CNAME records) and add to your DNS provider
3. Add SPF + DMARC records to DNS
4. Pass the identity ARN to the module via `ses_identity_arn`

The contact form Lambda will only send from the verified identity.

---

## Stripe Payments (Optional)

Enable with `enable_payments = true`. The module does **not** provision the
Secrets Manager secret — you must create and populate it out-of-band, then
pass its ARN in. Requires:

1. Stripe account with API keys
2. Secrets Manager secret you create yourself containing:
   ```json
   {
     "secret_key": "sk_...",
     "publishable_key": "pk_...",
     "webhook_secret": "whsec_..."
   }
   ```
3. Pass the Secrets Manager ARN as `stripe_secrets_arn`:
   ```hcl
   enable_payments    = true
   stripe_secrets_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:stripe-keys-XXXXX"
   ```

The module provisions:
- `payment` Lambda: accepts POST requests, returns client_secret for Stripe Elements
- `webhook` Lambda: verifies Stripe signatures, deduplicates events (DynamoDB idempotency table)
- Both sit behind `/api/stripe/*` routes on the CloudFront distribution

**Webhook Setup:**
- Deploy the module first
- In Stripe Dashboard → Webhooks → Add Endpoint, point at
  `https://{your-domain}/api/stripe/webhook`
- Select events: `payment_intent.*`, `customer.subscription.*`, `invoice.payment_*`

The webhook handler logs events to CloudWatch. Extend it with your business logic (email confirmations, database updates, etc.).

### Client-side request shape

Every browser request is a plain same-origin POST to a relative `/api/...` path.
No signing, no body hashing, no custom headers.

```js
const res = await fetch("/api/stripe/intent", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ amount: 1999, currency: "usd" }),
});
```

**See `examples/website/checkout.html` and `examples/website/contact.html` for working examples.**

---

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | ✓ | Short client identifier (lowercase alphanumeric + hyphens) |
| `domain_name` | string | ✓ | Apex domain (e.g. `example.com`) |
| `aliases` | list(string) | `[]` | CloudFront aliases (required when `dns_mode != "none"`). Example: `["example.com", "www.example.com"]` |
| `distribution_description` | string | `""` | CloudFront distribution description for console identification. Defaults to `"{name}-cdn"` |
| `enable_github_oidc` | bool | `false` | Create per-website GitHub Actions deploy role (requires `github_org` + `github_repo`) |
| `github_org` | string | `null` | GitHub organization or user (required when OIDC enabled) |
| `github_repo` | string | `null` | GitHub repository name (required when OIDC enabled) |
| `github_branch` | string | `"main"` | Branch allowed to deploy. `"main"` for main-only, `"*"` for any |
| `dns_mode` | string | `"none"` | DNS management: `none`, `self_managed`, or `external` |
| `certificate_arn` | string | `null` | Pre-validated ACM cert ARN (required when `dns_mode = "external"`) |
| `spa_mode` | bool | `false` | Return `/index.html` on 404/403 (single-page app routing) |
| `static_error_response_page_path` | string | `null` | Optional static error page path, for example `/404.html` |
| `static_error_response_codes` | list(number) | `[403, 404]` | Origin error codes that should render the static error page |
| `static_error_response_code` | number | `404` | Viewer-facing status returned with the static error page |
| `static_error_caching_min_ttl` | number | `60` | Minimum CloudFront cache TTL, in seconds, for static error responses |
| `price_class` | string | `"PriceClass_100"` | CloudFront price class |
| `is_ipv6_enabled` | bool | `true` | Enable IPv6 on the CloudFront distribution |
| `enable_waf` | bool | `false` | Enable WAF (requires `waf_acl_arn`) |
| `waf_acl_arn` | string | `null` | ARN of WAF Web ACL |
| `enable_site_password` | bool | `false` | Gate the static site with HTTP Basic Auth (required `site_password`). Does not affect API routes. |
| `site_password` | string (sensitive) | `null` | Password for Basic Auth when `enable_site_password = true`. |
| `site_password_username` | string | `"admin"` | Username for Basic Auth. |
| `enable_clean_urls` | bool | `false` | Serve the site with extensionless URLs and transparent subdirectory index resolution. See [Clean URLs](#clean-urls). |
| `enable_contact_form` | bool | `true` | Provision contact form Lambda |
| `contact_from_email` | string | `null` | SES sender (required if contact form enabled) |
| `contact_to_email` | string | `null` | Contact recipient (required if contact form enabled) |
| `ses_identity_arn` | string | `null` | ARN of SES verified identity |
| `enable_payments` | bool | `false` | Provision Stripe payment + webhook Lambdas |
| `stripe_secrets_arn` | string | `null` | Pre-existing Secrets Manager ARN with Stripe keys (required when `enable_payments = true`) |
| `payment_bundle_zip` | string | `null` | Path to esbuild-bundled payment Lambda zip (required when `enable_payments = true`) |
| `webhook_bundle_zip` | string | `null` | Path to esbuild-bundled webhook Lambda zip (required when `enable_payments = true`) |
| `contact_bundle_zip` | string | `null` | Path to contact Lambda zip (required when `enable_contact_form = true`) |
| `lambda_runtime` | string | `"nodejs24.x"` | Node.js runtime for all Lambdas |
| `lambda_architecture` | string | `"arm64"` | CPU architecture for all Lambdas (`arm64` or `x86_64`) |
| `api_throttle_burst` | number | `100` | API Gateway stage burst throttle (concurrent requests) |
| `api_throttle_rate` | number | `50` | API Gateway stage steady-state throttle (req/sec) |
| `csp_additional` | string | `""` | Extra CSP directives (e.g. `"connect-src https://api.example.com"`) |
| `csp_default_src` | list(string) | `["'self'"]` | Sources for the `default-src` CSP directive |
| `csp_script_src` | list(string) | `["'self'", "'unsafe-inline'", "https://js.stripe.com"]` | Sources for the `script-src` CSP directive |
| `csp_style_src` | list(string) | `["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"]` | Sources for the `style-src` CSP directive |
| `csp_img_src` | list(string) | `["'self'", "data:", "https:"]` | Sources for the `img-src` CSP directive |
| `csp_font_src` | list(string) | `["'self'", "data:", "https:", "https://fonts.gstatic.com"]` | Sources for the `font-src` CSP directive |
| `csp_connect_src` | list(string) | `["'self'", "https://api.stripe.com"]` | Base sources for the `connect-src` CSP directive |
| `csp_connect_src_additional` | list(string) | `[]` | Extra origins merged into `connect-src` alongside the module defaults |
| `csp_directive_order` | list(string) | Default CSP directive order | Ordered CSP directive names used when serializing the `Content-Security-Policy` header |
| `csp_media_src` | list(string) | `[]` | Sources for the `media-src` CSP directive |
| `csp_frame_src` | list(string) | `[]` | Sources for the `frame-src` CSP directive |
| `csp_frame_ancestors` | list(string) | `["'none'"]` | Sources for the `frame-ancestors` CSP directive |
| `csp_object_src` | list(string) | `[]` | Sources for the `object-src` CSP directive |
| `csp_base_uri` | list(string) | `["'self'"]` | Sources for the `base-uri` CSP directive |
| `csp_form_action` | list(string) | `["'self'"]` | Sources for the `form-action` CSP directive |
| `permissions_policy` | string | `""` | Optional `Permissions-Policy` response header value |
| `tags` | map(string) | `{}` | Tags for all resources |

---

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | S3 bucket name (for CI/CD uploads) |
| `distribution_id` | CloudFront distribution ID (for cache invalidation) |
| `distribution_domain` | CloudFront domain (`*.cloudfront.net`) |
| `distribution_hosted_zone_id` | CloudFront hosted zone ID for Route53 alias records |
| `website_url` | Primary website URL |
| `name_servers` | Route53 NS records (self_managed mode only) |
| `cert_validation_records` | ACM validation CNAMEs (for reference) |
| `contact_api_path` | CloudFront path for contact form |
| `payment_api_path` | CloudFront path for Stripe payment intent |
| `webhook_api_path` | CloudFront path for Stripe webhook |

---

## GitHub Actions OIDC (Per-Website Deploy Roles)

**Industry Standard Pattern:**
- **One OIDC provider** per AWS account (shared across all websites)
- **One IAM role per website**, with least-privilege scoped to:
  - The specific S3 bucket (sync only)
  - The specific CloudFront distribution (invalidation only)
- **Trust policy scoped to the specific GitHub repo + branch** (prevents cross-repo abuse)

This gives you per-website CloudTrail logs, blast-radius isolation, and clean audit trails — without manually creating roles for every client.

### Account Bootstrap (One-Time)

Before using `enable_github_oidc = true`, you must create the GitHub OIDC provider once per AWS account. This is a one-time operation:

```hcl
# bootstrap/main.tf — apply ONCE per AWS account
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
```

Apply this once. All client websites then use `data "aws_iam_openid_connect_provider"` to look it up.

### Per-Website Usage

Enable OIDC in your client repo's main.tf:

```hcl
module "website" {
  source = "git::https://github.com/rotordev-ops/rd-website-module.git?ref=v1.0.0"

  name        = "fwm"
  domain_name = "fortwoodmasjid.com"
  # ... other config

  enable_github_oidc = true
  github_org         = "rotordev-ops"
  github_repo        = "fwm-website"
  github_branch      = "main"  # only main branch can deploy

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "github_actions_role_arn" {
  value = module.website.github_actions_role_arn
}
```

After `terraform apply`, copy the role ARN from the output and set it as the `AWS_ROLE_ARN` secret in your GitHub repo.

### Trust Policy Scoping Options

| Setting | Trust Pattern | Use Case |
|---------|---------------|----------|
| `github_branch = "main"` | `repo:org/repo:ref:refs/heads/main` | **Production** (recommended) — only main branch deploys |
| `github_branch = "production"` | `repo:org/repo:ref:refs/heads/production` | Production branch with separate dev branch |
| `github_branch = "*"` | `repo:org/repo:*` | Any branch/PR/tag — only for dev/staging |

Branch scoping prevents PRs and feature branches from accidentally deploying to production.

### Permissions Granted

The role has **only**:
- `s3:ListBucket`, `s3:GetBucketLocation` on the website bucket
- `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on bucket objects
- `cloudfront:CreateInvalidation`, `cloudfront:GetInvalidation`, `cloudfront:ListInvalidations` on the distribution

No IAM permissions, no cross-bucket access, no other AWS services.

---

## GitHub Actions Workflow Setup

Copy `.github/workflows/deploy-website.yml.tpl` to `.github/workflows/deploy-website.yml` in your client repo and configure:

**Secrets:**
- `AWS_ROLE_ARN` - OIDC role ARN (from `terraform output github_actions_role_arn`)
- `TF_API_TOKEN` - Terraform Cloud API token
- `STRIPE_PUBLISHABLE_KEY` - (if payments enabled)

**Variables:**
- `TF_WORKSPACE_ID` - Terraform Cloud workspace ID (find in TF Cloud → Settings → General)

The workflow:
- Fetches Terraform outputs via TFC API
- Generates `config.js` with API endpoints
- Syncs HTML files (1-hour cache)
- Syncs static assets (1-year cache, immutable)
- Invalidates CloudFront `/*`

---

## Child Repository Maintenance

### Updating the Parent Module

When a new version is released, update your child repo's `main.tf`:

```hcl
module "website" {
  source = "git::https://github.com/rotordev-ops/rd-website-module.git?ref=v0.2.0"  # ← bump version
  # ... rest of config
}
```

Then:
```bash
terraform init  # downloads new module version
terraform plan  # review changes
terraform apply
```

### Syncing CI/CD Configuration

Periodically check for updates to:
- `.pre-commit-config.yaml` — new hooks or tool versions
- `.github/workflows/deploy-website.yml.tpl` — bug fixes or new features

```bash
# Get latest from parent repo
curl -o .pre-commit-config.yaml \
  https://raw.githubusercontent.com/rotordev-ops/rd-website-module/main/.pre-commit-config.yaml

# Review + commit if changed
git diff .pre-commit-config.yaml
git add .pre-commit-config.yaml && git commit -m "Update pre-commit config"
```

### Breaking Changes

Check [GitHub releases](https://github.com/rotordev-ops/rd-website-module/releases) for breaking changes before upgrading. May require:
- New input variables
- Changed output names
- Updated IAM permissions

#### v5 → v6 migration

v6 drops Lambda Layers and the `source_dir` input pattern in favor of
caller-built esbuild bundles. The runtime default also moves from Node
22.x to 24.x.

**Removed inputs:** `payment_source_dir`, `webhook_source_dir`,
`payment_layer_zip`, `webhook_layer_zip`.

**New required inputs** (when `enable_payments = true`):
`payment_bundle_zip`, `webhook_bundle_zip`. When
`enable_contact_form = true`: `contact_bundle_zip`.

**New optional inputs:** `lambda_runtime` (default `nodejs24.x`),
`lambda_architecture` (default `arm64`).

**Migration steps:**

1. Add an esbuild build step for each Lambda handler in your repo — see
   "Stripe handler contract" above for the canonical command.
2. Update your `main.tf`:
   ```hcl
   module "website" {
     source  = "app.terraform.io/<org>/rd-website-module/aws"
     version = "6.0.0"

     # was: payment_source_dir, payment_layer_zip
     payment_bundle_zip = "${path.root}/../payment-lambda/payment/dist/payment.zip"
     webhook_bundle_zip = "${path.root}/../payment-lambda/webhook/dist/webhook.zip"
     contact_bundle_zip = "${path.root}/../contact-lambda/dist/contact.zip"
     # rest unchanged
   }
   ```
3. Either build the zips before `terraform apply` (CI step) or wire a
   `null_resource` with `local-exec = "pnpm run package"` and a
   `triggers` hash so Terraform rebuilds when source files change.
4. The `terraform plan` will show Lambda functions replaced (new
   `source_code_hash`) and Lambda Layers destroyed. Cold-start will
   drop ~30–50%.

---

## Examples

- `examples/minimal/` - S3 + CloudFront (no DNS, no contact form)
- `examples/with-contact/` - + Route53 + contact form
- `examples/with-payments/` - + Stripe payment integration

---

## Clean URLs

Set `enable_clean_urls = true` for **directory-style, no-slash canonical**
URLs — the shape used by Shopify, Stripe, Vercel, Netlify, and every
Jamstack static site generator (Next.js export, Hugo, Gatsby, Astro).

Implemented as a CloudFront Function on `viewer-request` —
sub-millisecond, no Lambda cold start, no charge beyond included
requests.

| Request              | Result                                            |
|----------------------|---------------------------------------------------|
| `/about`             | rewrite → `/about/index.html` (200)               |
| `/admin`             | rewrite → `/admin/index.html` (200)               |
| `/blog/post-1`       | rewrite → `/blog/post-1/index.html` (200)         |
| `/about/`            | 301 → `/about` (strip trailing slash)             |
| `/about.html`        | 301 → `/about` (canonical)                        |
| `/about/index.html`  | 301 → `/about`                                    |
| `/about.html?id=1`   | 301 → `/about?id=1` (querystring preserved)       |
| `/style.css`, `/a.js`| passthrough (dot in last segment = asset)         |
| `/`                  | passthrough → served via `default_root_object`    |

### Site layout

Every page ships as `path/index.html`:

```
site/
├── index.html              → /
├── about/index.html        → /about
├── contact/index.html      → /contact
├── blog/
│   ├── index.html          → /blog
│   └── post-1/index.html   → /blog/post-1
└── admin/
    ├── index.html          → /admin
    └── orders/index.html   → /admin/orders
```

Relative hrefs (`<a href="contact">`) resolve correctly because the
browser URL stays extensionless, so `/` is always the base.

### Composition with `enable_site_password`

When both flags are set, the same function runs basic-auth first, then
the rewrite. CloudFront permits only one function per event type per
cache behavior, so composing the two is required.

### SEO

301s from `.html` / trailing-slash / `/index.html` to the canonical
extensionless form prevent duplicate-content indexing. Update any
`<link rel="canonical">` tags and `sitemap.xml` entries to match.

### Migration from the old flat-file mode

Earlier module versions rewrote `/about` → `/about.html`, which broke
on directory pages like `/admin`. The new directory-style resolver is a
breaking change for sites that keep flat `.html` files at root. Move
each flat page into its own directory:

```
mv about.html     about/index.html
mv contact.html   contact/index.html
mv product-x.html product-x/index.html
```

No in-page link changes required if hrefs were already extensionless.

**Composition with `enable_site_password`:** when both flags are set, the
same function runs basic-auth first, then the rewrite. CloudFront only
permits one function per event type per cache behavior, so composing the
two is required.

**SEO:** the 301 from `/foo.html` to `/foo` prevents duplicate-content
indexing. After enabling, update any `<link rel="canonical">` tags and
`sitemap.xml` entries to the extensionless form.

**Upgrading from a prior module version:** the CloudFront Function resource
is renamed (`basic_auth` → `viewer_request`) and its AWS name changes from
`<name>-basic-auth` to `<name>-viewer-request`. A `moved` block migrates
Terraform state; the underlying function is replaced with
`create_before_destroy` to avoid an auth-gate gap during apply.

---

## Static Error Responses

For static content sites, set `static_error_response_page_path` to a
deployed error page such as `/404.html`. Private S3 origins return `403
AccessDenied` for missing objects, so the default
`static_error_response_codes = [403, 404]` maps both origin failures to the
same branded error page while preserving a viewer-facing `404`.

Example:

```hcl
static_error_response_page_path = "/404.html"
static_error_response_code      = 404
```

Use `spa_mode` instead only when client-side routing should return
`/index.html` with HTTP `200` for unknown paths.

---

## Security Notes

- ✅ S3 bucket completely private (all Block Public Access enabled)
- ✅ CloudFront OAC for S3 (only CF can read objects)
- ✅ API Gateway HTTP API is public, but each endpoint has its own security:
  - Contact form: rate-limited at stage level
  - Payment intent: Stripe authentication (client confirms payment)
  - Webhook: Stripe signature verification (cryptographic)
- ✅ API Gateway stage-level throttling (`api_throttle_burst` /
  `api_throttle_rate`) to bound cost on a flood
- ✅ Webhook idempotency via DynamoDB conditional writes
- ✅ IAM policies scoped to specific resources (no wildcards on actions)
- ✅ HSTS with preload + 1 year max-age
- ✅ CSP with `frame-ancestors 'none'` + `form-action 'self'`
- ✅ TLS 1.2 minimum (modern ciphers via AWS defaults)
- ✅ CloudWatch Logs retention (14 days) for both Lambdas and API Gateway access logs
- ✅ SES SendEmail scoped to verified identity (no account-wide send)

**Not Included (by design):**
- WAF (optional, add via `waf_acl_arn`)
- CloudFront logging (optional, enable in `modules/website-foundations/cloudfront.tf`)
- KMS encryption (not worth cost for public content)
- Multi-region (not needed for static sites)

---

## Development & Testing

```bash
# Format check
terraform fmt -check -recursive .

# Validate examples
terraform -chdir=examples/minimal init -backend=false
terraform -chdir=examples/minimal validate

# TFLint
tflint --recursive .

# Trivy scan
trivy fs --security-checks config .

# Deploy test infrastructure (with throwaway TFC workspace)
cd examples/minimal
terraform init
terraform plan
terraform apply
# ... verify in AWS console ...
terraform destroy
```

---

## Stripe handler contract

The payment and webhook Lambdas are **caller-built**. You supply a
pre-bundled zip via `payment_bundle_zip` / `webhook_bundle_zip`, and the
module attaches it to the shared API Gateway HTTP API as an `AWS_PROXY`
integration.

### Runtime
- Node.js 24.x, arm64, 256 MB, 10s timeout (all overridable via
  `lambda_runtime`, `lambda_architecture`, and module-level memory/timeout
  knobs in `modules/payment-lambda/variables.tf`)
- Handler entrypoint: `index.handler` (ESM, `index.mjs`)

### Build contract (esbuild, 2026 standard)

The zip must contain a **single-file `index.mjs`** with all dependencies
tree-shaken and inlined — no `node_modules`, no transitive peer-dep
surprises at runtime. Any package manager works at build time (pnpm
recommended); only the esbuild output ships to Lambda.

```bash
# in the directory containing your handler's package.json + index.mjs:
pnpm install --frozen-lockfile
pnpm exec esbuild index.mjs \
  --bundle \
  --platform=node \
  --target=node24 \
  --format=esm \
  --outfile=dist/index.mjs \
  --banner:js="import { createRequire } from 'module'; const require = createRequire(import.meta.url);"
cd dist && zip -r ../payment.zip .
```

The `--banner:js=...` shim is required because some AWS SDK v3 internals
(`@smithy/util-stream`, etc.) still use `require()`. Without the banner,
bundled ESM output breaks on Lambda.

> **Why not a Lambda Layer?** Layers for the AWS SDK are now an
> anti-pattern: they require the deployed `node_modules` to be perfectly
> flat (pnpm's symlinked layout breaks on Lambda), they slow cold-start,
> and tree-shaking SDK v3 with esbuild drops a 60 MB dep to <1 MB. Reserve
> layers for genuinely large binaries (Sharp, Puppeteer) or the AWS
> Parameters & Secrets Extension.

Reference handlers live at `modules/payment-lambda/src/payment/` and
`modules/payment-lambda/src/webhook/` — copy them into your project if
you need a starting point.

### Environment variables provided by the module
| Var                  | Who gets it  | Contents |
|----------------------|--------------|----------|
| `STRIPE_SECRETS_ARN` | payment + webhook  | ARN of a Secrets Manager secret whose JSON value has at least `{ secret_key, webhook_secret }`. |
| `IDEMPOTENCY_TABLE`  | webhook only | Name of a DynamoDB table with hash key `event_id` (string) and TTL attribute `expires_at`. Use with `PutItem` + `attribute_not_exists` for once-only processing. |

### IAM permissions granted
- **payment:** `secretsmanager:GetSecretValue` on `STRIPE_SECRETS_ARN`, plus CloudWatch Logs.
- **webhook:** `secretsmanager:GetSecretValue` on `STRIPE_SECRETS_ARN`,
  `dynamodb:PutItem` on the idempotency table, plus CloudWatch Logs.

### Request shape (payment Lambda)
API Gateway HTTP API v2 event shape (`event.requestContext.http.method`,
`event.body`, etc.). The bundled handler:
1. Rejects non-POST.
2. Parses JSON body `{ amount (int cents, >=50), currency, metadata }`.
3. Creates a PaymentIntent and returns `{ client_secret, payment_intent_id }`.

A custom handler is free to accept any body shape — e.g. `{ items: [...] }` — as
long as it returns `client_secret` to the browser.

### Request shape (webhook Lambda)
API Gateway HTTP API v2 event shape. Headers are lowercase-keyed; the Stripe
signature arrives as `event.headers["stripe-signature"]`. The raw body is in
`event.body`, base64-decoded when `event.isBase64Encoded` is true.

---

## License

Internal use only.
---

## Rabbit Tracker Website

A simple static website is included in `docs/` to track your rabbit's last known location.

- `docs/index.html` — static tracker UI
- `docs/app.js` — stores sightings in browser local storage
- `docs/styles.css` — styles for the tracker app

The site is published from the `gh-pages` branch.

To run locally:
```bash
cd /Users/andyh/Websites/Pippin/docs
python3 -m http.server 8000
```

Visit the live site at:
`https://orky63.github.io/Pippin/`
