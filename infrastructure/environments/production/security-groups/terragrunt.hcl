include "root" { path = find_in_parent_folders("root.hcl") }
locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}
dependency "vpc" {
  config_path  = "../vpc"
  mock_outputs = { vpc_id = "vpc-00000000" }
}
terraform { source = "../../../_modules//security-groups" }
inputs = {
  project = local.common.locals.project
  env     = local.account.locals.env
  vpc_id  = dependency.vpc.outputs.vpc_id
}
