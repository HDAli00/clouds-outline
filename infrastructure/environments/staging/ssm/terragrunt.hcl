include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "s3" {
  config_path  = "../s3"
  mock_outputs = { uploads_bucket_id = "outline-staging-uploads" }
}

# CloudFront dependency removed — no domain yet. Re-add when a domain is configured:
# dependency "cloudfront" {
#   config_path  = "../cloudfront"
#   mock_outputs = { distribution_domain = "d0000000000000.cloudfront.net" }
# }

dependency "alb" {
  config_path  = "../alb"
  mock_outputs = { alb_dns_name = "outline-staging-alb.eu-west-1.elb.amazonaws.com" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "rds" {
  config_path = "../rds"
  mock_outputs = {
    endpoint    = "outline-staging-postgres.cluster-xxxx.us-east-1.rds.amazonaws.com:5432"
    db_name     = "outline"
    username    = "outline"
    db_password = "placeholder-set-on-apply"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "elasticache" {
  config_path = "../elasticache"
  mock_outputs = {
    primary_endpoint = "outline-staging.xxxx.ng.0001.use1.cache.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

terraform {
  source = "../../../_modules//ssm"
}

# ---------------------------------------------------------------------------
# Outline environment variables — stored as SSM Parameters at /outline/staging/*
#
# NON-SECRETS (String — constructed from Terraform outputs, visible in state):
#   URL, CDN_URL, AWS_REGION, AWS_S3_UPLOAD_BUCKET_NAME, AWS_S3_UPLOAD_BUCKET_URL,
#   SMTP_HOST, SMTP_PORT, SMTP_FROM_EMAIL
#
# SECRETS (SecureString with lifecycle.ignore_changes — set once on first apply,
#          never overwritten by Terraform after that):
#   SECRET_KEY, UTILS_SECRET  → still need manual CLI steps (truly random secrets)
#   DATABASE_URL, REDIS_URL   → auto-constructed from RDS/ElastiCache outputs below
#   SMTP_USERNAME, SMTP_PASSWORD → set via CLI after creating SES SMTP credentials
#
#   Remaining manual secrets (run once after first apply):
#     aws ssm put-parameter --name /outline/staging/SECRET_KEY \
#       --value "$(openssl rand -hex 32)" --type SecureString --overwrite
#     aws ssm put-parameter --name /outline/staging/UTILS_SECRET \
#       --value "$(openssl rand -hex 32)" --type SecureString --overwrite
# ---------------------------------------------------------------------------
inputs = {
  project = local.common.locals.project
  env     = local.account.locals.env

  # App URLs — using ALB DNS directly (no domain/CloudFront yet)
  app_url           = "http://${dependency.alb.outputs.alb_dns_name}"
  cloudfront_domain = ""  # empty — SSM module falls back to cdn_url
  cdn_url           = "http://${dependency.alb.outputs.alb_dns_name}"

  # AWS
  aws_region           = local.common.locals.aws_region
  s3_upload_bucket     = dependency.s3.outputs.uploads_bucket_id
  s3_upload_bucket_url = "https://s3.${local.common.locals.aws_region}.amazonaws.com"

  # SMTP — Amazon SES. SMTP_USERNAME/PASSWORD are SES SMTP credentials set via CLI.
  smtp_host       = "email-smtp.${local.common.locals.aws_region}.amazonaws.com"
  smtp_port       = "587"
  smtp_from_email = "noreply@localhost"  # placeholder — update when domain is configured

  # RDS components — module constructs DATABASE_URL internally
  rds_username = dependency.rds.outputs.username
  rds_password = dependency.rds.outputs.db_password
  rds_endpoint = dependency.rds.outputs.endpoint
  rds_dbname   = dependency.rds.outputs.db_name

  # ElastiCache component — module constructs REDIS_URL internally
  elasticache_endpoint = dependency.elasticache.outputs.primary_endpoint
}
