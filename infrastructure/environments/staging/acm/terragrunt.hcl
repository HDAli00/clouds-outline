include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

# ACM reads the hosted zone ID directly from account.hcl to avoid a circular
# dependency with the route53 module (route53 → cloudfront → acm → route53).

terraform {
  source = "../../../_modules//acm"
}

inputs = {
  project = local.common.locals.project
  env     = local.account.locals.env
  domain  = local.account.locals.domain
  zone_id = local.account.locals.hosted_zone_id
}
