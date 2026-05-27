resource "aws_ecs_cluster" "this" {
  name = "${var.project}-${var.env}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project}-${var.env}-cluster" }
}

# ---------------------------------------------------------------------------
# Look up SSM parameter ARNs by the well-known path convention.
# The SSM module owns these parameters; ECS reads them here at plan time.
# Path: /${var.project}/${var.env}/VAR_NAME  (e.g. /outline/staging/SECRET_KEY)
# ---------------------------------------------------------------------------
locals {
  ssm_prefix = "/${var.project}/${var.env}"

  # Env-vars that Outline reads at startup, sourced from SSM Parameter Store.
  # The ECS execution role grants the container agent permission to fetch them.
  ssm_env_vars = [
    "SECRET_KEY",
    "UTILS_SECRET",
    "DATABASE_URL",
    "REDIS_URL",
    "URL",
    "CDN_URL",
    "AWS_REGION",
    "AWS_S3_UPLOAD_BUCKET_NAME",
    "AWS_S3_UPLOAD_BUCKET_URL",
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_FROM_EMAIL",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
  ]
}

data "aws_ssm_parameter" "outline" {
  for_each = toset(local.ssm_env_vars)
  name     = "${local.ssm_prefix}/${each.key}"
}

locals {
  common_secrets = [
    for name in local.ssm_env_vars : {
      name      = name
      valueFrom = data.aws_ssm_parameter.outline[name].arn
    }
  ]

  common_env = [
    { name = "PORT",                     value = "3000" },
    { name = "NODE_ENV",                 value = var.node_env },
    { name = "FILE_STORAGE",             value = "s3" },
    { name = "AWS_S3_ACL",               value = "private" },
    { name = "AWS_S3_FORCE_PATH_STYLE",  value = "false" },  # real AWS S3, not compatible endpoint
    { name = "PGSSLMODE",                value = "require" }, # RDS requires TLS
    { name = "FORCE_HTTPS",              value = "false" },   # ALB/CloudFront handles TLS termination
  ]
}

# ---------------------------------------------------------------------------
# CloudWatch log groups
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.project}/${var.env}/web"
  retention_in_days = 30
  tags              = { Service = "web" }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.project}/${var.env}/worker"
  retention_in_days = 30
  tags              = { Service = "worker" }
}

# ---------------------------------------------------------------------------
# Web Process task definition
# SERVICES=web,websockets,collaboration
# Runs: Web API + WebSocket + Collaboration + Admin (Bull Board at /admin)
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "web" {
  family                   = "${var.project}-${var.env}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.web_task_role_arn

  container_definitions = jsonencode([{
    name      = "outline-web"
    image     = "${var.ecr_repository_url}:latest"
    essential = true

    environment = concat(local.common_env, [
      { name = "SERVICES", value = "web,websockets,collaboration" }
    ])

    secrets = local.common_secrets

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.web.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "web"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:3000/_health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = { Name = "${var.project}-${var.env}-web-task" }
}

# ---------------------------------------------------------------------------
# Worker Process task definition
# SERVICES=worker  (includes Worker queue consumer + Cron scheduled tasks)
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project}-${var.env}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.worker_task_role_arn

  container_definitions = jsonencode([{
    name      = "outline-worker"
    image     = "${var.ecr_repository_url}:latest"
    essential = true

    environment = concat(local.common_env, [
      { name = "SERVICES", value = "worker" }
    ])

    secrets = local.common_secrets

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.worker.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "worker"
      }
    }
  }])

  tags = { Name = "${var.project}-${var.env}-worker-task" }
}

# ---------------------------------------------------------------------------
# ECS Services
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "web" {
  name            = "${var.project}-${var.env}-web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.web_min_capacity
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.fargate_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.web_tg_arn
    container_name   = "outline-web"
    container_port   = 3000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition, desired_count]  # Managed by CI/CD
  }

  tags = { Name = "${var.project}-${var.env}-web-service" }
}

resource "aws_ecs_service" "worker" {
  name            = "${var.project}-${var.env}-worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.fargate_sg_id]
    assign_public_ip = false
  }

  deployment_minimum_healthy_percent = 100  # Never have zero workers
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition]  # Managed by CI/CD
  }

  tags = { Name = "${var.project}-${var.env}-worker-service" }
}

# ---------------------------------------------------------------------------
# Auto-scaling for Web process
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "web" {
  max_capacity       = var.web_max_capacity
  min_capacity       = var.web_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "web_cpu" {
  name               = "${var.project}-${var.env}-web-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
