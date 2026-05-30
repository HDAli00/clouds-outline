# Shared values across ALL environments and ALL modules.
# Read via: read_terragrunt_config(find_in_parent_folders("_common.hcl"))

locals {
  project    = "outline"
  aws_region = "eu-west-1"

  # Availability zones used for multi-AZ subnets
  azs = ["eu-west-1a", "eu-west-1b"]

  # CIDR blocks are defined per-environment in each account.hcl
  # to avoid VPC conflicts when staging and production share the same AWS account.
  # staging:    10.0.0.0/16
  # production: 10.1.0.0/16
}
