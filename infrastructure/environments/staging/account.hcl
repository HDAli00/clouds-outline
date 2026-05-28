# Staging environment — account-level config
# Read by root terragrunt.hcl via find_in_parent_folders("account.hcl")
#
# BEFORE FIRST APPLY:
#   1. Set account_id  → run: aws sts get-caller-identity --query Account --output text
#   2. Set domain      → the DNS name you want Outline to be served from
#   3. Set hosted_zone_id → the Route 53 hosted zone that owns the domain
#                           run: aws route53 list-hosted-zones-by-name --dns-name example.com
#
# These three values are the only things you must supply manually.
# Everything else is derived or managed by Terragrunt/Terraform.

locals {
  env            = "staging"
  account_id     = get_aws_account_id()                # Reads from current AWS credentials
  domain         = "staging.wiki.example.com"       # Subdomain you want Outline served on
  hosted_zone_id = "Z1PA6795UKMFR9"                 # Route53 hosted zone for the apex domain

  # CIDR blocks — staging uses 10.0.x.x range
  vpc_cidr                  = "10.0.0.0/16"
  public_subnet_cidrs       = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
  private_data_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]

  # Instance sizing — free tier eligible (db.t3.micro = 750h/month free, 20 GB)
  rds_instance_class        = "db.t3.micro"
  rds_allocated_storage     = 20
  rds_max_allocated_storage = 20  # disable autoscaling on free tier
  redis_node_type           = "cache.t2.micro"
  ecs_web_cpu          = 512
  ecs_web_memory       = 1024
  ecs_worker_cpu       = 256
  ecs_worker_memory    = 512
  ecs_web_min_capacity = 1
  ecs_web_max_capacity = 4
}
