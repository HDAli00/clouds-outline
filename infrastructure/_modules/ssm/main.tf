# ---------------------------------------------------------------------------
# Helper locals — path prefix for all parameters
# Parameters live at: /outline/{env}/APP_VAR_NAME
# ECS task definitions reference these via secrets[] using the ARN.
# ---------------------------------------------------------------------------
locals {
  prefix = "/${var.project}/${var.env}"

  # Construct URLs from components when provided, otherwise fall back to the
  # pre-built string variables. This avoids Terragrunt dependency.* interpolation
  # issues in wiring files.
  database_url = var.rds_endpoint != "" ? "postgres://${var.rds_username}:${var.rds_password}@${var.rds_endpoint}/${var.rds_dbname}?sslmode=disable" : var.database_url
  redis_url    = var.elasticache_endpoint != "" ? "redis://${var.elasticache_endpoint}:6379" : var.redis_url
  cdn_url      = var.cloudfront_domain != "" ? "https://${var.cloudfront_domain}" : var.cdn_url
}

# ---------------------------------------------------------------------------
# Non-secret config — SSM String (readable without KMS)
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "app_url" {
  name  = "${local.prefix}/URL"
  type  = "String"
  value = var.app_url
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "cdn_url" {
  name  = "${local.prefix}/CDN_URL"
  type  = "String"
  value = local.cdn_url
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "${local.prefix}/AWS_REGION"
  type  = "String"
  value = var.aws_region
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "s3_upload_bucket" {
  name  = "${local.prefix}/AWS_S3_UPLOAD_BUCKET_NAME"
  type  = "String"
  value = var.s3_upload_bucket
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "s3_upload_bucket_url" {
  name  = "${local.prefix}/AWS_S3_UPLOAD_BUCKET_URL"
  type  = "String"
  value = coalesce(var.s3_upload_bucket_url, "https://s3.amazonaws.com")
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "smtp_host" {
  name  = "${local.prefix}/SMTP_HOST"
  type  = "String"
  value = var.smtp_host
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "smtp_port" {
  name  = "${local.prefix}/SMTP_PORT"
  type  = "String"
  value = var.smtp_port
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "smtp_from_email" {
  name  = "${local.prefix}/SMTP_FROM_EMAIL"
  type  = "String"
  value = var.smtp_from_email
  tags  = { Env = var.env }

  lifecycle {
    ignore_changes = [value]  # Prevent Terraform from resetting manually updated email address
  }
}


# ---------------------------------------------------------------------------
# Secrets — SSM SecureString (encrypted with default KMS key)
# These are injected into ECS task definitions via secrets[] block.
# IMPORTANT: Set real values via CLI after initial apply:
#   aws ssm put-parameter --name /outline/staging/SECRET_KEY --value "..." --type SecureString --overwrite
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "secret_key" {
  name      = "${local.prefix}/SECRET_KEY"
  type      = "SecureString"
  value     = var.secret_key
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }

  lifecycle {
    ignore_changes = [value]  # Prevent Terraform from resetting manually updated secrets
  }
}

resource "aws_ssm_parameter" "utils_secret" {
  name      = "${local.prefix}/UTILS_SECRET"
  type      = "SecureString"
  value     = var.utils_secret
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "database_url" {
  name      = "${local.prefix}/DATABASE_URL"
  type      = "SecureString"
  value     = local.database_url
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "redis_url" {
  name      = "${local.prefix}/REDIS_URL"
  type      = "SecureString"
  value     = local.redis_url
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "smtp_username" {
  name      = "${local.prefix}/SMTP_USERNAME"
  type      = "SecureString"
  value     = var.smtp_username
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "smtp_password" {
  name      = "${local.prefix}/SMTP_PASSWORD"
  type      = "SecureString"
  value     = var.smtp_password
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_id" {
  name      = "${local.prefix}/GOOGLE_CLIENT_ID"
  type      = "SecureString"
  value     = var.google_client_id
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_secret" {
  name      = "${local.prefix}/GOOGLE_CLIENT_SECRET"
  type      = "SecureString"
  value     = var.google_client_secret
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "slack_client_id" {
  name      = "${local.prefix}/SLACK_CLIENT_ID"
  type      = "SecureString"
  value     = var.slack_client_id
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "slack_client_secret" {
  name      = "${local.prefix}/SLACK_CLIENT_SECRET"
  type      = "SecureString"
  value     = var.slack_client_secret
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "oidc_client_id" {
  name      = "${local.prefix}/OIDC_CLIENT_ID"
  type      = "SecureString"
  value     = var.oidc_client_id
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "oidc_client_secret" {
  name      = "${local.prefix}/OIDC_CLIENT_SECRET"
  type      = "SecureString"
  value     = var.oidc_client_secret
  overwrite = true
  tags      = { Env = var.env, Secret = "true" }
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "oidc_auth_uri" {
  name  = "${local.prefix}/OIDC_AUTH_URI"
  type  = "String"
  value = var.oidc_auth_uri
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "oidc_token_uri" {
  name  = "${local.prefix}/OIDC_TOKEN_URI"
  type  = "String"
  value = var.oidc_token_uri
  tags  = { Env = var.env }
}

resource "aws_ssm_parameter" "oidc_userinfo_uri" {
  name  = "${local.prefix}/OIDC_USERINFO_URI"
  type  = "String"
  value = var.oidc_userinfo_uri
  tags  = { Env = var.env }
}
