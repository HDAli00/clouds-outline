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
  default     = true
  description = "Whether to create the GitHub OIDC provider. Set to false in secondary environments to avoid conflicts."
}
