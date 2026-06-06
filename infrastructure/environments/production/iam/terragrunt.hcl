include "root" { path = find_in_parent_folders("root.hcl") }
locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}
dependency "s3" {
  config_path  = "../s3"
  mock_outputs = { uploads_bucket_arn = "arn:aws:s3:::outline-production-uploads", static_bucket_arn = "arn:aws:s3:::outline-production-static" }
}
dependency "ecr" {
  config_path  = "../ecr"
  mock_outputs = { repository_arn = "arn:aws:ecr:us-east-1:123:repository/outline-production" }
}
terraform { source = "../../../_modules//iam" }
inputs = {
  project                        = local.common.locals.project
  env                            = local.account.locals.env
  uploads_bucket_arn             = dependency.s3.outputs.uploads_bucket_arn
  static_bucket_arn              = dependency.s3.outputs.static_bucket_arn
  ecr_repository_arn             = dependency.ecr.outputs.repository_arn
  github_org                     = "HDAli00"
  github_repo                    = "clouds-outline"
  create_github_oidc_provider    = true  # Production creates its own separate OIDC provider
}
