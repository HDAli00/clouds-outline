include "root" { path = find_in_parent_folders("root.hcl") }
locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}
dependency "vpc" {
  config_path  = "../vpc"
  mock_outputs = { private_data_subnet_ids = ["subnet-0", "subnet-1"] }
}
dependency "security_groups" {
  config_path  = "../security-groups"
  mock_outputs = { rds_sg_id = "sg-0" }
}
terraform { source = "../../../_modules//rds" }
inputs = {
  project            = local.common.locals.project
  env                = local.account.locals.env
  instance_class     = local.account.locals.rds_instance_class
  subnet_ids         = dependency.vpc.outputs.private_data_subnet_ids
  security_group_ids = [dependency.security_groups.outputs.rds_sg_id]
  multi_az           = true  # production: Multi-AZ enabled
}
