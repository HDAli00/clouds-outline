include "root" {
  path = find_in_parent_folders("root.hcl")
}

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
  mock_outputs = { redis_sg_id = "sg-0" }
}

terraform {
  source = "../../../_modules//elasticache"
}

inputs = {
  project            = local.common.locals.project
  env                = local.account.locals.env
  node_type          = local.account.locals.redis_node_type
  subnet_ids         = dependency.vpc.outputs.private_data_subnet_ids
  security_group_ids = [dependency.security_groups.outputs.redis_sg_id]
  num_replicas       = 0  # staging: no replica to save cost
}
