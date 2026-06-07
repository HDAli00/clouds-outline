variable "project"              { type = string }
variable "env"                  { type = string }
variable "uploads_bucket_arn"   { type = string }
variable "static_bucket_arn"    { type = string }
variable "ecr_repository_arn"   { type = string }
variable "github_org" {
  type    = string
  default = "HDAli00"
}
variable "github_repo" {
  type    = string
  default = "clouds-outline"
}
variable "create_github_oidc_provider" {
  type        = bool
  default     = false
  description = "Whether to create the GitHub OIDC provider. Set to false to use existing provider via data source. Set to true only when creating OIDC provider for the first time."
}

variable "github_oidc_thumbprint" {
  type        = string
  default     = "6938fd4d98bab03faadb97b34396831e3780aea1"
  description = "GitHub OIDC certificate thumbprint. Update if GitHub rotates their certificate. Get current: echo | openssl s_client -servername token.actions.githubusercontent.com -connect token.actions.githubusercontent.com:443 2>/dev/null | openssl x509 -fingerprint -noout | sed 's/://g' | awk -F= '{print tolower($2)}'"
}
