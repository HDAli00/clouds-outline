# ──────────────────────────────────────────────────────────────────────────────
# ACM — DISABLED until a real domain is configured.
#
# Staging currently serves over the raw ALB DNS name (HTTP only), so there is no
# TLS certificate to issue yet. Leaving this stack active would make
# `terragrunt run-all apply` request a cert for the placeholder domain and block
# on DNS validation against a hosted zone we don't own.
#
# To re-enable: set a real `domain` + `hosted_zone_id` in account.hcl, remove
# `skip = true`, and uncomment the block below.
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
# # ACM reads the hosted zone ID directly from account.hcl to avoid a circular
# # dependency with the route53 module (route53 → cloudfront → acm → route53).
#
# terraform {
#   source = "../../../_modules//acm"
# }
#
# inputs = {
#   project = local.common.locals.project
#   env     = local.account.locals.env
#   domain  = local.account.locals.domain
#   zone_id = local.account.locals.hosted_zone_id
# }
