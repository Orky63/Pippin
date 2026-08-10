name: Deploy Website

on:
  push:
    branches:
      - main
    paths:
      - "index.html"
      - "*.html"
      - "styles.css"
      - "script.js"
      - "images/**"
      - "fonts/**"
      - "manifest.json"
      - "robots.txt"
      - "sitemap.xml"
      - ".github/workflows/deploy-website.yml"
  workflow_dispatch:

permissions:
  id-token: write # Required for AWS OIDC
  contents: read  # Required for actions/checkout to fetch the repo

jobs:
  deploy:
    name: Deploy to S3 + CloudFront
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          role-session-name: github-actions
          aws-region: us-east-1

      - name: Fetch Terraform outputs
        id: tf-outputs
        env:
          TF_API_TOKEN: ${{ secrets.TF_API_TOKEN }}
          TF_WORKSPACE_ID: ${{ vars.TF_WORKSPACE_ID }}
        run: |
          set -euo pipefail

          if [ -z "${TF_WORKSPACE_ID:-}" ]; then
            echo "::error::TF_WORKSPACE_ID variable is not set. Configure it in repo Settings → Variables."
            exit 1
          fi

          # Use the state-version-outputs endpoint which returns actual values.
          # The /current-state-version endpoint returns metadata only (output IDs, no values).
          RESPONSE=$(curl -sf \
            --header "Authorization: Bearer $TF_API_TOKEN" \
            "https://app.terraform.io/api/v2/workspaces/$TF_WORKSPACE_ID/current-state-version-outputs") || {
              echo "::error::Failed to fetch outputs from Terraform Cloud. Check TF_API_TOKEN has 'Read state outputs' permission on this workspace, and TF_WORKSPACE_ID is the workspace ID (ws-xxxx), not the name."
              exit 1
            }

          # Response shape: { "data": [ { "attributes": { "name": "...", "value": ... } }, ... ] }
          if [ "$(echo "$RESPONSE" | jq '.data | length')" = "0" ]; then
            echo "::error::No outputs found in Terraform Cloud workspace. Has 'terraform apply' been run?"
            exit 1
          fi

          get_output() {
            echo "$RESPONSE" | jq -r --arg name "$1" '.data[] | select(.attributes.name == $name) | .attributes.value // empty'
          }

          BUCKET=$(get_output bucket_name)
          DIST_ID=$(get_output distribution_id)
          CONTACT_ENDPOINT=$(get_output contact_api_path)
          PAYMENT_ENDPOINT=$(get_output payment_api_path)

          # Default optional endpoints to "null" string for the config.js template step
          CONTACT_ENDPOINT=${CONTACT_ENDPOINT:-null}
          PAYMENT_ENDPOINT=${PAYMENT_ENDPOINT:-null}

          if [ -z "$BUCKET" ] || [ -z "$DIST_ID" ]; then
            echo "::error::Required outputs (bucket_name, distribution_id) missing from TFC state. Check your main.tf exposes both as outputs."
            exit 1
          fi

          echo "bucket_name=$BUCKET" >> $GITHUB_OUTPUT
          echo "distribution_id=$DIST_ID" >> $GITHUB_OUTPUT
          echo "contact_endpoint=$CONTACT_ENDPOINT" >> $GITHUB_OUTPUT
          echo "payment_endpoint=$PAYMENT_ENDPOINT" >> $GITHUB_OUTPUT

      - name: Generate config.js
        env:
          CONTACT_API: ${{ steps.tf-outputs.outputs.contact_endpoint }}
          PAYMENT_API: ${{ steps.tf-outputs.outputs.payment_endpoint }}
          STRIPE_KEY: ${{ secrets.STRIPE_PUBLISHABLE_KEY }}
        run: |
          cat > config.js << 'EOF'
          window.CONTACT_API_ENDPOINT = "${{ secrets.WEBSITE_URL }}$CONTACT_API";
          window.STRIPE_API_ENDPOINT = "${{ secrets.WEBSITE_URL }}$PAYMENT_API";
          window.STRIPE_PUBLISHABLE_KEY = "$STRIPE_KEY";
          EOF

      - name: Deploy static assets
        run: |
          aws s3 sync . s3://${{ steps.tf-outputs.outputs.bucket_name }}/ \
            --exclude ".git/*" \
            --exclude ".github/*" \
            --exclude "terraform/*" \
            --exclude "README.md" \
            --exclude "*.html" \
            --exclude "config.js" \
            --exclude ".gitignore" \
            --cache-control "public,max-age=31536000,immutable" \
            --delete

      - name: Deploy HTML files
        run: |
          # Order matters: aws s3 sync evaluates --exclude/--include left-to-right
          # and later flags override earlier ones. Always --exclude "*" FIRST, then
          # --include the files you want, otherwise nothing gets uploaded.
          aws s3 sync . s3://${{ steps.tf-outputs.outputs.bucket_name }}/ \
            --exclude "*" \
            --include "*.html" \
            --cache-control "public,max-age=3600,must-revalidate" \
            --content-type "text/html"

      - name: Deploy config.js
        run: |
          aws s3 cp config.js s3://${{ steps.tf-outputs.outputs.bucket_name }}/config.js \
            --cache-control "no-cache,no-store,must-revalidate" \
            --content-type "application/javascript"

      - name: Invalidate CloudFront
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ steps.tf-outputs.outputs.distribution_id }} \
            --paths "/*"
