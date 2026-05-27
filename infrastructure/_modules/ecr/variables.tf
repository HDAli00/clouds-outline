variable "project" { type = string }
variable "env"     { type = string }
variable "image_retention_count" {
  type    = number
  default = 10
}
