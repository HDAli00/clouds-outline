include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

terraform {
  source = "../../../_modules//vpc"
}

inputs = {
  project                   = local.common.locals.project
  env                       = local.account.locals.env
  vpc_cidr                  = local.common.locals.vpc_cidr
  azs                       = local.common.locals.azs
  public_subnet_cidrs       = local.common.locals.public_subnet_cidrs
  private_app_subnet_cidrs  = local.common.locals.private_app_subnet_cidrs
  private_data_subnet_cidrs = local.common.locals.private_data_subnet_cidrs
}
