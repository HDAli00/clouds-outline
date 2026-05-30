terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Auto-generated at first apply — stored in Terraform state (encrypted).
# Never changes after creation thanks to lifecycle.ignore_changes in the resource.
resource "random_password" "db" {
  length  = 32
  special = false  # keeps password URL-safe for the DATABASE_URL connection string

  lifecycle { ignore_changes = [length, special] }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.env}-rds-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.project}-${var.env}-rds-subnet-group" }
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.project}-${var.env}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = { Name = "${var.project}-${var.env}-pg16" }
}

resource "aws_db_instance" "this" {
  identifier        = "${var.project}-${var.env}-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.instance_class
  db_name           = var.db_name
  username          = var.db_username
  password          = random_password.db.result

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project}-${var.env}-final-snapshot"

  tags = { Name = "${var.project}-${var.env}-postgres" }
}
