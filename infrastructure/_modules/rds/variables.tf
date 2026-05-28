variable "project"              { type = string }
variable "env"                  { type = string }
variable "instance_class"       { type = string }
variable "db_name" {
  type    = string
  default = "outline"
}
variable "db_username" {
  type    = string
  default = "outline"
}
variable "subnet_ids"         { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "multi_az" {
  type    = bool
  default = true
}
variable "backup_retention_period" {
  type    = number
  default = 7
}
variable "allocated_storage" {
  type    = number
  default = 100
}
variable "max_allocated_storage" {
  type    = number
  default = 500
}
