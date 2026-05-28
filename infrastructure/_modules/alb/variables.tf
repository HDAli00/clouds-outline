variable "project"          { type = string }
variable "env"              { type = string }
variable "vpc_id"           { type = string }
variable "public_subnet_ids"{ type = list(string) }
variable "alb_sg_id"        { type = string }
variable "certificate_arn"  {
  type    = string
  default = null
  description = "ACM certificate ARN. If null, ALB serves HTTP only (no HTTPS listener)."
}
