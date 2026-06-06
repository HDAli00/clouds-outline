data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# ECS Execution Role — used by ECS agent to pull images and read secrets
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project}-${var.env}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_base" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_ssm" {
  name = "ssm-read"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${var.env}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com" }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# ECS Web Task Role — S3 presigned URL generation (Web + Worker both need this)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_web_task" {
  name = "${var.project}-${var.env}-ecs-web-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_web_s3" {
  name = "s3-uploads"
  role = aws_iam_role.ecs_web_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [var.uploads_bucket_arn, "${var.uploads_bucket_arn}/*"]
    }]
  })
}

# ---------------------------------------------------------------------------
# ECS Worker Task Role — S3 for exports, imports, avatar processing
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_worker_task" {
  name = "${var.project}-${var.env}-ecs-worker-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_worker_s3" {
  name = "s3-uploads"
  role = aws_iam_role.ecs_worker_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [var.uploads_bucket_arn, "${var.uploads_bucket_arn}/*"]
    }]
  })
}

# ---------------------------------------------------------------------------
# GitHub Actions Deploy Role — OIDC, no stored credentials
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github.arn
}

# ---------------------------------------------------------------------------
# Dedicated GitHub Actions Role per Environment
# Restricted by OIDC subject claim to environment-specific CI/CD runs only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions" {
  name = "${var.project}-${var.env}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # OIDC subject includes environment context: repo:org/repo:environment:staging (or :production)
          # This prevents staging workflows from assuming the production role
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:environment:${var.env}"
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Deny policy: Prevent this role from accessing resources tagged with a different environment
resource "aws_iam_role_policy" "github_actions_deny_cross_env" {
  name = "deny-cross-environment"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDifferentEnvironmentTag"
        Effect = "Deny"
        Action = [
          "ecr:*",
          "ecs:*",
          "s3:*",
          "rds:*",
          "elasticache:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:ResourceTag/Environment" = var.env
          }
          StringLike = {
            "aws:ResourceTag/Environment" = ["staging", "production"]
          }
        }
      }
    ]
  })
}

# Allow policy: Deploy and infrastructure management for current environment
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "ECRPushImage"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
        Resource = var.ecr_repository_arn
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = var.env
          }
        }
      },
      {
        Sid      = "ECSManagement"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = var.env
          }
        }
      },
      {
        Sid      = "IAMPassRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_web_task.arn, aws_iam_role.ecs_worker_task.arn]
      },
      {
        Sid      = "S3StaticAssets"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [var.static_bucket_arn, "${var.static_bucket_arn}/*"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = var.env
          }
        }
      },
      {
        Sid      = "CloudFrontInvalidation"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = var.env
          }
        }
      },
      {
        Sid      = "TerraformStateAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::outline-tfstate-*",
          "arn:aws:s3:::outline-tfstate-*/*"
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = "${var.env}/*"
          }
        }
      }
    ]
  })
}
