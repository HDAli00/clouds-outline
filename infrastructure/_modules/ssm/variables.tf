variable "project" { type = string }
variable "env"     { type = string }

# --- Non-secret app config (SSM String) ---
variable "app_url"          { type = string }
variable "cdn_url"          { type = string }
variable "aws_region"       { type = string }
variable "s3_upload_bucket" { type = string }

variable "s3_upload_bucket_url" {
  type    = string
  default = "" # https://s3.amazonaws.com (for presigned URLs)
}
variable "smtp_host" {
  type    = string
  default = ""
}
variable "smtp_port" {
  type    = string
  default = "587"
}
variable "smtp_from_email" {
  type    = string
  default = ""
}

# --- Secrets (SSM SecureString — set once on first apply, lifecycle.ignore_changes prevents overwrites) ---
# secret_key / utils_secret MUST be set manually via CLI after first apply (truly random, never auto-generated).
# database_url / redis_url are auto-constructed from RDS/ElastiCache outputs in the env wiring files.
variable "secret_key" {
  type      = string
  sensitive = true
  default   = "0000000000000000000000000000000000000000000000000000000000000000"
}
variable "utils_secret" {
  type      = string
  sensitive = true
  default   = "0000000000000000000000000000000000000000000000000000000000000000"
}
variable "database_url" {
  type      = string
  sensitive = true
  default   = ""
}
variable "redis_url" {
  type      = string
  sensitive = true
  default   = ""
}

# --- URL component variables (alternative to passing pre-built URLs) ---
# When these are provided, the module constructs DATABASE_URL and REDIS_URL internally,
# avoiding Terragrunt string-interpolation issues with dependency.* references.
variable "rds_username" {
  type    = string
  default = ""
}
variable "rds_password" {
  type      = string
  sensitive = true
  default   = ""
}
variable "rds_endpoint" {
  type    = string
  default = ""
}
variable "rds_dbname" {
  type    = string
  default = ""
}
variable "elasticache_endpoint" {
  type    = string
  default = ""
}
variable "cloudfront_domain" {
  type    = string
  default = ""
}
variable "smtp_username" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "smtp_password" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "google_client_id" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "google_client_secret" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "slack_client_id" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "slack_client_secret" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "oidc_client_id" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "placeholder"
}
variable "oidc_auth_uri" {
  type    = string
  default = "placeholder"
}
variable "oidc_token_uri" {
  type    = string
  default = "placeholder"
}
variable "oidc_userinfo_uri" {
  type    = string
  default = "placeholder"
}
