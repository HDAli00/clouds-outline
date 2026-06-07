include "root" { path = find_in_parent_folders("root.hcl") }
locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}
terraform { source = "../../../_modules//s3" }
inputs = {
  project              = local.common.locals.project
  env                  = local.account.locals.env
  uploads_cors_origins = ["https://${local.account.locals.domain}"]
}
