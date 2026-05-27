variable "project"           { type = string }
variable "env"               { type = string }
variable "domain"            { type = string }
variable "alb_dns_name"      { type = string }
variable "alb_zone_id"       { type = string }
variable "static_bucket_id"  { type = string }
variable "certificate_arn"   { type = string }
variable "price_class" {
  type    = string
  default = "PriceClass_100" # US, Canada, Europe
}
