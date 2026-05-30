include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "vpc" {
  config_path  = "../vpc"
  mock_outputs = { vpc_id = "vpc-00000000", public_subnet_ids = ["subnet-0", "subnet-1"] }
}
dependency "security_groups" {
  config_path  = "../security-groups"
  mock_outputs = { alb_sg_id = "sg-0" }
}
# ACM dependency removed — no domain yet. Re-add when a real domain is configured:
# dependency "acm" {
#   config_path  = "../acm"
#   mock_outputs = { certificate_arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000" }
# }

terraform {
  source = "../../../_modules//alb"
}

inputs = {
  project           = local.common.locals.project
  env               = local.account.locals.env
  vpc_id            = dependency.vpc.outputs.vpc_id
  public_subnet_ids = dependency.vpc.outputs.public_subnet_ids
  alb_sg_id         = dependency.security_groups.outputs.alb_sg_id
  # certificate_arn omitted — ALB will serve HTTP only until a domain is configured
}
