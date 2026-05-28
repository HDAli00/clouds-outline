# ──────────────────────────────────────────────────────────────────────────────
# CloudFront — DISABLED until a real domain is configured.
#
# The distribution depends on the ACM certificate (acm stack), which is itself
# disabled while staging has no domain. Traffic currently goes straight to the
# ALB DNS name, so no CDN is provisioned yet.
#
# To re-enable: re-enable the acm stack, remove `skip = true`, and uncomment
# the block below.
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
# dependency "alb" {
#   config_path  = "../alb"
#   mock_outputs = { alb_dns_name = "x.us-east-1.elb.amazonaws.com", alb_zone_id = "Z1234" }
# }
# dependency "s3" {
#   config_path  = "../s3"
#   mock_outputs = { static_bucket_id = "outline-staging-static-assets" }
# }
# dependency "acm" {
#   config_path  = "../acm"
#   mock_outputs = { certificate_arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000" }
#   mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
# }
#
# terraform {
#   source = "../../../_modules//cloudfront"
# }
#
# inputs = {
#   project          = local.common.locals.project
#   env              = local.account.locals.env
#   domain           = local.account.locals.domain
#   alb_dns_name     = dependency.alb.outputs.alb_dns_name
#   alb_zone_id      = dependency.alb.outputs.alb_zone_id
#   static_bucket_id = dependency.s3.outputs.static_bucket_id
#   certificate_arn  = dependency.acm.outputs.certificate_arn
#   price_class      = "PriceClass_100"  # US, Canada, Europe only (cost saving)
# }
