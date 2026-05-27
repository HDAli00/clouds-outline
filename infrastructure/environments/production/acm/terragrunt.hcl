include "root" { path = find_in_parent_folders("root.hcl") }
locals {
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}
# zone_id comes directly from account.hcl — avoids circular dep with route53 module
terraform { source = "../../../_modules//acm" }
inputs = {
  domain  = local.account.locals.domain
  zone_id = local.account.locals.hosted_zone_id
}
