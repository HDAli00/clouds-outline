## Overview

This infrastructure demonstrates a modern CI/CD workflow built to experiment Terraform, Terragrunt, AWS, and GitHub Actions. The goal is to show how infrastructure-as-code, containerization, and automated deployment can work together.

Below is the Complete architecture of the infrastructure.

![Outline-AWS-Infrastructure](images/Outline%20AWS%20Infrastrcuture.png)

Two environments run on AWS free tier:

- **Staging** - Auto-deployed on every PR (live preview of changes)
- **Production** - Deployed on merge to main (with manual approval gate)

## How It Works

### Push a change to GitHub

When you push code or modify infrastructure files:

1. **Infrastructure changes** (if touching `infrastructure/**`):
   - GitHub Actions runs Terragrunt to plan the changes
   - Staging auto-applies immediately (because it's a live preview)
   - Production shows a plan and waits for approval before applying

2. **Application changes** (code updates):
   - Docker image builds using the Dockerfile
   - Image gets pushed to AWS ECR (Elastic Container Registry)
   - Staging deploys the new image automatically
   - Production deploys after approval

### Architecture Components

| Component          | Technology                       | Purpose                                              |
| ------------------ | -------------------------------- | ---------------------------------------------------- |
| Web Server         | ECS Fargate + Koa                | Node.js API and frontend served behind load balancer |
| Database           | RDS PostgreSQL 16                | Data persistence                                     |
| Cache              | ElastiCache Redis 7.1            | Session storage and real-time collaboration          |
| Load Balancer      | AWS ALB                          | Route traffic to web servers, health checks          |
| Container Registry | ECR (Elastic Container Registry) | Store and deploy Docker images                       |
| Secrets            | SSM Parameter Store              | Secure storage for database credentials, keys, etc.  |

### Terraform Modules

Infrastructure is organized into modules for reusability and clarity:

| Module          | Manages                                                               |
| --------------- | --------------------------------------------------------------------- |
| **vpc**         | Network, subnets, security groups, NAT gateway                        |
| **ecs**         | Fargate cluster, web & worker tasks, auto-scaling (target 60% CPU)    |
| **rds**         | PostgreSQL 16 database                                                |
| **elasticache** | Redis replication group with encryption                               |
| **alb**         | Application load balancer, target groups, DNS                         |
| **ecr**         | Container image repositories for staging and production               |
| **ssm**         | Parameter Store for app secrets (database URL, auth keys, SMTP creds) |
| **iam**         | Roles and permissions for ECS tasks to access RDS, Redis, S3, etc.    |

Each module is configured per-environment in `environments/staging/` and `environments/production/`.

### GitHub Actions Workflows

**Infrastructure Workflow** (.github/workflows/infrastructure.yml)

| Event                            | Staging Behavior              | Production Behavior           |
| -------------------------------- | ----------------------------- | ----------------------------- |
| Pull request (infrastructure/\*) | Plan + Auto-apply             | Plan only (PR comment)        |
| Push to main (infrastructure/\*) | (already handled via PR)      | Plan + Wait for approval      |
| Manual dispatch                  | Plan or apply (choose via UI) | Plan or apply (choose via ui) |

Staging auto-applies because it's a live preview - developers test changes immediately. Production requires manual approval before any changes are made.

**Deploy Workflow** (.github/workflows/deploy.yml)

| Event           | Action                                                                              |
| --------------- | ----------------------------------------------------------------------------------- |
| Pull request    | Build Docker image, push to staging ECR, deploy to staging ECS                      |
| Push to main    | Build Docker image, promote to production ECR, deploy to production (approval gate) |
| Manual dispatch | Rollback using previous image tag (no rebuild)                                      |

Images are built once and promoted between environments using digest-based copying. Production never rebuilds - it pulls the exact same image that was tested in staging.

### Security & Deployment Strategy

| Aspect              | How It Works                                                        |
| ------------------- | ------------------------------------------------------------------- |
| **Credentials**     | GitHub Actions uses OIDC to assume AWS role (no static keys stored) |
| **Secrets**         | ECS tasks fetch from SSM Parameter Store at startup                 |
| **Approval Gates**  | GitHub Environments enforce manual review before production deploy  |
| **Image Promotion** | Production uses staging image by digest (bit-for-bit identical)     |
| **Rollback**        | Manual dispatch with old image tag, retag as latest, force-deploy   |

### Free Tier Configuration

Both staging and production use AWS free tier eligible resources to minimize costs during development:

- **Database:** db.t3.micro
- **Cache:** cache.t3.micro
- **Storage:** 20 GB

This setup is ideal for learning and experimentation but should be upgraded to production-grade resources (larger instances, multi-AZ, automated backups) when handling real traffic.

## Learning Purpose

This infrastructure demonstrates:

1. **Infrastructure as Code** - All resources defined in Terraform, version controlled, reviewable
2. **Modular Design** - Reusable modules that can be composed and customized per environment
3. **CI/CD Automation** - Workflow that tests and deploys code automatically
4. **Security Practices** - No static credentials, approval gates, parameter store for secrets
5. **Cost Optimization** - Free tier resources suitable for development and experimentation

## OIDC

Instead of storing a password (AWS access key) in GitHub for deployments, you set up a "trust agreement" between GitHub and AWS. I configured **federated identity** using OIDC. GitHub acts as the identity provider (IdP); AWS IAM is the service provider (SP). At runtime, GitHub's OIDC endpoint mints a short-lived JWT with claims including the repo, branch, and workflow context. AWS STS validates the token signature against the registered IdP thumbprint, verifies the `aud` claim matches `sts.amazonaws.com`, and evaluates the IAM role's trust policy against the `sub` claim (`repo:HDAli00/clouds-outline:*`). On success, STS returns ephemeral credentials via `AssumeRoleWithWebIdentity`. This eliminates long-lived static credentials entirely, no secret rotation, no credential leakage risk, full auditability via CloudTrail.

![Outline-AWS-Architecture](images/CICD%20process.png)
