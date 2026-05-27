variable "project"    { type = string }
variable "env"        { type = string }
variable "domain"     { type = string }
variable "cf_domain" {
  type        = string
  description = "CloudFront distribution domain name."
}
variable "cf_zone_id" {
  type        = string
  description = "CloudFront hosted zone ID."
}
