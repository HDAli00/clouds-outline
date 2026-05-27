variable "project" { type = string }
variable "env"     { type = string }

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to use."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for public subnets (ALB, NAT Gateways)."
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for private app subnets (ECS tasks)."
}

variable "private_data_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for private data subnets (RDS, ElastiCache)."
}
