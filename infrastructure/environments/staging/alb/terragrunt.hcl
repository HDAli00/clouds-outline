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
dependency "acm" {
  config_path  = "../acm"
  mock_outputs = { certificate_arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

terraform {
  source = "../../../_modules//alb"
}

inputs = {
  project           = local.common.locals.project
  env               = local.account.locals.env
  vpc_id            = dependency.vpc.outputs.vpc_id
  public_subnet_ids = dependency.vpc.outputs.public_subnet_ids
  alb_sg_id         = dependency.security_groups.outputs.alb_sg_id
  certificate_arn   = dependency.acm.outputs.certificate_arn
}
