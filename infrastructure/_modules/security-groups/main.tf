# sg-alb: public-facing, allows HTTP/HTTPS from anywhere
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.env}-sg-alb"
  description = "ALB - allow HTTP/HTTPS from internet"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.env}-sg-alb" }
}

# sg-fargate: ECS tasks — only allow traffic from the ALB on port 3000
resource "aws_security_group" "fargate" {
  name        = "${var.project}-${var.env}-sg-fargate"
  description = "ECS Fargate tasks - allow port 3000 from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Allow traffic from ALB only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (ECR pull, S3, Secrets Manager via NAT)"
  }

  tags = { Name = "${var.project}-${var.env}-sg-fargate" }
}

# sg-rds: PostgreSQL — only from Fargate tasks
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.env}-sg-rds"
  description = "RDS PostgreSQL - allow 5432 from Fargate only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.fargate.id]
    description     = "PostgreSQL from ECS tasks only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.env}-sg-rds" }
}

# sg-redis: ElastiCache Redis — only from Fargate tasks
resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.env}-sg-redis"
  description = "ElastiCache Redis - allow 6379 from Fargate only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.fargate.id]
    description     = "Redis from ECS tasks only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.env}-sg-redis" }
}
