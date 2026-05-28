# Production environment — account-level config
# Read by root terragrunt.hcl via find_in_parent_folders("account.hcl")
#
# BEFORE FIRST APPLY:
#   1. Set account_id      → aws sts get-caller-identity --query Account --output text
#   2. Set domain          → the apex domain for your Outline instance
#   3. Set hosted_zone_id  → aws route53 list-hosted-zones-by-name --dns-name example.com

locals {
  env            = "production"
  account_id     = get_aws_account_id()                # Reads from current AWS credentials
  domain         = "wiki.example.com"               # Apex domain for your Outline instance
  hosted_zone_id = "Z1PA6795UKMFR9"                 # Route53 hosted zone for the apex domain

  # CIDR blocks — production uses 10.1.x.x range (avoids conflict with staging in same account)
  vpc_cidr                  = "10.1.0.0/16"
  public_subnet_cidrs       = ["10.1.1.0/24", "10.1.2.0/24"]
  private_app_subnet_cidrs  = ["10.1.10.0/24", "10.1.11.0/24"]
  private_data_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24"]

  # Instance sizing — production grade
  rds_instance_class   = "db.r6g.large"
  redis_node_type      = "cache.r6g.large"
  ecs_web_cpu          = 1024
  ecs_web_memory       = 2048
  ecs_worker_cpu       = 512
  ecs_worker_memory    = 1024
  ecs_web_min_capacity = 2
  ecs_web_max_capacity = 8
}
