# ──────────────────────────────────────────────────────────────────────────────
# Route53 — DISABLED until a real domain is configured.
#
# This stack creates alias records pointing the domain at the CloudFront
# distribution (also disabled). With no owned hosted zone / domain yet, staging
# is reached directly via the ALB DNS name.
#
# To re-enable: re-enable the acm + cloudfront stacks, remove `skip = true`,
# and uncomment the block below.
# ──────────────────────────────────────────────────────────────────────────────
include "root" {
  path = find_in_parent_folders("root.hcl")
}

skip = true

# locals {
#   common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
#   account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
# }
#
# dependency "cloudfront" {
#   config_path  = "../cloudfront"
#   mock_outputs = { distribution_domain = "d1234.cloudfront.net", hosted_zone_id = "Z2FDTNDATAQYW2" }
# }
#
# terraform { source = "../../../_modules//route53" }
#
# inputs = {
#   project    = local.common.locals.project
#   env        = local.account.locals.env
#   domain     = local.account.locals.domain
#   cf_domain  = dependency.cloudfront.outputs.distribution_domain
#   cf_zone_id = dependency.cloudfront.outputs.hosted_zone_id
# }
