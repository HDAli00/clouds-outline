include "root" { path = find_in_parent_folders("root.hcl") }
locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "s3" {
  config_path  = "../s3"
  mock_outputs = { uploads_bucket_id = "outline-production-uploads", uploads_bucket_arn = "arn:aws:s3:::outline-production-uploads" }
}

dependency "cloudfront" {
  config_path  = "../cloudfront"
  mock_outputs = { distribution_domain = "d0000000000000.cloudfront.net" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "rds" {
  config_path = "../rds"
  mock_outputs = {
    endpoint    = "outline-production-postgres.cluster-xxxx.us-east-1.rds.amazonaws.com:5432"
    db_name     = "outline"
    username    = "outline"
    db_password = "placeholder-set-on-apply"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "elasticache" {
  config_path = "../elasticache"
  mock_outputs = {
    primary_endpoint = "outline-production.xxxx.ng.0001.use1.cache.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform { source = "../../../_modules//ssm" }

# Remaining manual secrets (run once after first apply):
#   aws ssm put-parameter --name /outline/production/SECRET_KEY \
#     --value "$(openssl rand -hex 32)" --type SecureString --overwrite
#   aws ssm put-parameter --name /outline/production/UTILS_SECRET \
#     --value "$(openssl rand -hex 32)" --type SecureString --overwrite
inputs = {
  project = local.common.locals.project
  env     = local.account.locals.env

  app_url              = "https://${local.account.locals.domain}"
  cloudfront_domain    = dependency.cloudfront.outputs.distribution_domain
  aws_region           = local.common.locals.aws_region
  s3_upload_bucket     = dependency.s3.outputs.uploads_bucket_id
  s3_upload_bucket_url = "https://s3.${local.common.locals.aws_region}.amazonaws.com"
  smtp_host            = "email-smtp.${local.common.locals.aws_region}.amazonaws.com"
  smtp_port            = "587"
  smtp_from_email      = "noreply@${local.account.locals.domain}"

  # RDS components — module constructs DATABASE_URL internally
  rds_username = dependency.rds.outputs.username
  rds_password = dependency.rds.outputs.db_password
  rds_endpoint = dependency.rds.outputs.endpoint
  rds_dbname   = dependency.rds.outputs.db_name

  # ElastiCache component — module constructs REDIS_URL internally
  elasticache_endpoint = dependency.elasticache.outputs.primary_endpoint
}
