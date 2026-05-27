# Shared values across ALL environments and ALL modules.
# Read via: read_terragrunt_config(find_in_parent_folders("_common.hcl"))

locals {
  project    = "outline"
  aws_region = "eu-west-1"

  # Availability zones used for multi-AZ subnets
  azs = ["eu-west-1a", "eu-west-1b"]

  # CIDR blocks — consistent across envs, isolated by VPC
  vpc_cidr                  = "10.0.0.0/16"
  public_subnet_cidrs       = ["10.0.1.0/24", "10.0.2.0/24"]   # ALB, NAT GWs
  private_app_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"] # ECS tasks
  private_data_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"] # RDS, ElastiCache
}
