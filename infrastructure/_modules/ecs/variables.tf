variable "project"              { type = string }
variable "env"                  { type = string }
variable "node_env" {
  type    = string
  default = "production" # "production" or "staging"
}
variable "aws_region"           { type = string }
variable "ecr_repository_url"   { type = string }
variable "private_app_subnet_ids" { type = list(string) }
variable "fargate_sg_id"        { type = string }
variable "execution_role_arn"   { type = string }
variable "web_task_role_arn"    { type = string }
variable "worker_task_role_arn" { type = string }
variable "web_tg_arn"           { type = string }

# Web process sizing
variable "web_cpu"              { type = number }
variable "web_memory"           { type = number }
variable "web_min_capacity"     { type = number }
variable "web_max_capacity"     { type = number }

# Worker process sizing
variable "worker_cpu"           { type = number }
variable "worker_memory"        { type = number }

variable "worker_min_capacity" {
  type        = number
  description = "Minimum number of worker tasks"
}

variable "worker_max_capacity" {
  type        = number
  description = "Maximum number of worker tasks"
}
