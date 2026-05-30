include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("_common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "vpc" {
  config_path  = "../vpc"
  mock_outputs = { private_app_subnet_ids = ["subnet-0", "subnet-1"] }
}
dependency "security_groups" {
  config_path  = "../security-groups"
  mock_outputs = { fargate_sg_id = "sg-0" }
}
dependency "iam" {
  config_path  = "../iam"
  mock_outputs = { execution_role_arn = "arn:aws:iam::000000000000:role/x", web_task_role_arn = "arn:aws:iam::000000000000:role/x", worker_task_role_arn = "arn:aws:iam::000000000000:role/x" }
}
dependency "ecr" {
  config_path  = "../ecr"
  mock_outputs = { repository_url = "123.dkr.ecr.us-east-1.amazonaws.com/outline" }
}
dependency "alb" {
  config_path  = "../alb"
  mock_outputs = { web_tg_arn = "arn:aws:elasticloadbalancing:us-east-1:000000000000:targetgroup/x/y" }
}
# SSM must be fully applied before ECS — the ECS module reads all SSM parameters
# via data sources at plan time, so they must exist in AWS before ECS runs.
dependency "ssm" {
  config_path  = "../ssm"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

terraform {
  source = "../../../_modules//ecs"
}

inputs = {
  project                = local.common.locals.project
  env                    = local.account.locals.env
  aws_region             = local.common.locals.aws_region
  ecr_repository_url     = dependency.ecr.outputs.repository_url
  private_app_subnet_ids = dependency.vpc.outputs.private_app_subnet_ids
  fargate_sg_id          = dependency.security_groups.outputs.fargate_sg_id
  execution_role_arn     = dependency.iam.outputs.execution_role_arn
  web_task_role_arn      = dependency.iam.outputs.web_task_role_arn
  worker_task_role_arn   = dependency.iam.outputs.worker_task_role_arn
  web_tg_arn             = dependency.alb.outputs.web_tg_arn

  web_cpu          = local.account.locals.ecs_web_cpu
  web_memory       = local.account.locals.ecs_web_memory
  web_min_capacity = local.account.locals.ecs_web_min_capacity
  web_max_capacity = local.account.locals.ecs_web_max_capacity
  worker_cpu       = local.account.locals.ecs_worker_cpu
  worker_memory    = local.account.locals.ecs_worker_memory
  node_env         = "production"  # Must be "production" for Outline to serve built assets
}
