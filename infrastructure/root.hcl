# Root Terragrunt config — inherited by all child modules via find_in_parent_folders()
# Defines remote state backend (S3 native locking) and generates the AWS provider.

locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

# ---------------------------------------------------------------------------
# Remote state: one S3 key per module path, S3 native locking (no DynamoDB needed)
# Requires Terraform >= 1.10 and AWS provider >= 5.x
# ---------------------------------------------------------------------------
remote_state {
  backend = "s3"

  config = {
    bucket       = "outline-tfstate-${local.account.locals.account_id}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.common.locals.aws_region
    encrypt      = true
    use_lockfile = true
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ---------------------------------------------------------------------------
# AWS provider — generated into every child module automatically.
# A second alias (aws.us_east_1) is included so the ACM module can pin
# its certificate resources to us-east-1 (required by CloudFront).
# ---------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.common.locals.aws_region}"

      default_tags {
        tags = {
          Project     = "${local.common.locals.project}"
          Environment = "${local.account.locals.env}"
          ManagedBy   = "Terragrunt"
          Repository  = "HDAli00/clouds-outline"
        }
      }
    }

    # Alias used exclusively by the ACM module — CloudFront requires certs in us-east-1
    provider "aws" {
      alias  = "us_east_1"
      region = "us-east-1"

      default_tags {
        tags = {
          Project     = "${local.common.locals.project}"
          Environment = "${local.account.locals.env}"
          ManagedBy   = "Terragrunt"
          Repository  = "HDAli00/clouds-outline"
        }
      }
    }
  EOF
}
