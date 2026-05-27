variable "project"     { type = string }
variable "env"         { type = string }
variable "uploads_cors_origins" {
  type    = list(string)
  default = ["*"]
  description = "Allowed origins for uploads bucket CORS."
}
