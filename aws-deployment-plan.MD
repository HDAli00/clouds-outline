# Outline — AWS Deployment Plan

## Application Services Overview

Outline runs as a single Docker image (Node 24, port 3000) with services selected via the `SERVICES` env var.

| Service | Env Value | Role | HTTP? | Scaling |
|---------|-----------|------|-------|---------|
| Web + API | `web,api` | REST API, auth, SPA serving, health check | Yes | Horizontal, stateless |
| WebSockets | `websockets` | Socket.io real-time events at `/realtime` | Yes (upgrade) | Horizontal via Redis adapter |
| Collaboration | `collaboration` | Y.js collaborative editing at `/collaboration` | Yes (upgrade) | Horizontal via Redis |
| Worker | `worker` | Bull queue consumer, background jobs | No | Scale on queue depth |
| Cron | `cron` | Scheduled tasks (cleanup, analytics) | No | Single instance only |

---

## Architecture Diagram

```
                         ┌──────────────┐
                         │   Route 53   │
                         │ wiki.example │
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │  CloudFront  │
                         │  (ACM SSL)   │
                         └──┬───────┬───┘
                            │       │
              ┌─────────────▼─┐   ┌─▼──────────────┐
              │  S3 Bucket    │   │  ALB (Origin)   │
              │ Static Assets │   │  Internal LB    │
              │ /static/*     │   └──┬──────┬───┬───┘
              │ /fonts/*      │      │      │   │
              │ /images/*     │      │      │   │
              └───────────────┘      │      │   │
                                     │      │   │
         ┌───────────────────────────┘      │   └──────────────────┐
         │                                  │                      │
  ┌──────▼──────────┐  ┌───────────────────▼──┐  ┌────────────────▼──┐
  │  Fargate: Web   │  │ Fargate: Realtime    │  │  Fargate: Worker  │
  │  SERVICES=      │  │ SERVICES=            │  │  SERVICES=worker  │
  │  web,api        │  │ websockets,          │  │                   │
  │                 │  │ collaboration        │  ├───────────────────┤
  │  /api/*         │  │                      │  │  Fargate: Cron    │
  │  /auth/*        │  │  /realtime (ws)      │  │  SERVICES=cron    │
  │  /* (SPA)       │  │  /collaboration (ws) │  │  (single instance)│
  │  /_health       │  │                      │  │                   │
  └────────┬────────┘  └──────────┬───────────┘  └────────┬──────────┘
           │                      │                        │
           └──────────┬───────────┴────────────────────────┘
                      │
            ┌─────────▼──────────┐
            │   Private Subnets  │
            │                    │
            │  ┌──────────────┐  │
            │  │ RDS Postgres │  │
            │  │  (Multi-AZ)  │  │
            │  └──────────────┘  │
            │                    │
            │  ┌──────────────┐  │
            │  │ ElastiCache  │  │
            │  │   Redis      │  │
            │  └──────────────┘  │
            │                    │
            │  ┌──────────────┐  │
            │  │  S3 Bucket   │  │
            │  │  Uploads     │  │
            │  └──────────────┘  │
            └────────────────────┘
```

---

## AWS Services Mapping

### Compute — ECS Fargate

| Fargate Service | App Services | vCPU | Memory | Min/Max Tasks | Scaling Trigger |
|-----------------|-------------|------|--------|---------------|-----------------|
| `outline-web` | `web,api` | 0.5 | 1 GB | 2 / 8 | CPU > 60% |
| `outline-realtime` | `websockets,collaboration` | 0.5 | 1 GB | 2 / 6 | Connection count |
| `outline-worker` | `worker` | 0.5 | 1 GB | 1 / 4 | Queue depth |
| `outline-cron` | `cron` | 0.25 | 0.5 GB | 1 / 1 | None (singleton) |

All services share the same ECR container image, differentiated only by the `SERVICES` env var.

Nginx runs as a **sidecar container** in the web and realtime tasks for gzip compression, request buffering, and static file headers.

### Networking — VPC

| Component | Configuration |
|-----------|--------------|
| VPC CIDR | `10.0.0.0/16` |
| Public Subnets | `10.0.1.0/24`, `10.0.2.0/24` (2 AZs) — ALB, NAT Gateways |
| Private App Subnets | `10.0.10.0/24`, `10.0.11.0/24` (2 AZs) — Fargate tasks |
| Private Data Subnets | `10.0.20.0/24`, `10.0.21.0/24` (2 AZs) — RDS, ElastiCache |
| NAT Gateways | 1 per AZ (for Fargate outbound: ECR pulls, S3, external auth) |
| Internet Gateway | 1 (for ALB inbound) |

### Load Balancing — ALB

| Listener | Rule | Target Group |
|----------|------|-------------|
| HTTPS :443 | `/realtime*` | `outline-realtime` (sticky sessions) |
| HTTPS :443 | `/collaboration*` | `outline-realtime` (sticky sessions) |
| HTTPS :443 | `/*` (default) | `outline-web` |
| HTTP :80 | All | Redirect to HTTPS |

Health check: `GET /_health` expecting `200 OK`

### CDN — CloudFront

| Behavior | Origin | Cache | Notes |
|----------|--------|-------|-------|
| `/static/*` | S3 static bucket (OAC) | 1 year, immutable | Built Vite assets with content hashes |
| `/images/*`, `/fonts/*` | S3 static bucket (OAC) | 7 days | Public assets |
| `/*` (default) | ALB | No cache (forward all) | API, auth, SPA, WebSocket upgrade |

SSL via ACM certificate on the CloudFront distribution. The `CDN_URL` env var is set to the CloudFront domain so the app rewrites asset paths.

### Database — RDS PostgreSQL

| Setting | Value |
|---------|-------|
| Engine | PostgreSQL 16 |
| Instance | `db.r6g.large` (2 vCPU, 16 GB) |
| Multi-AZ | Yes (standby replica) |
| Storage | 100 GB gp3, auto-scaling to 500 GB |
| Backups | 7-day retention, daily snapshots |
| Encryption | At rest (KMS) + in transit (SSL) |

### Cache & Queues — ElastiCache Redis

| Setting | Value |
|---------|-------|
| Engine | Redis 7.x |
| Node Type | `cache.r6g.large` |
| Replicas | 1 read replica (Multi-AZ) |
| Encryption | At rest + in transit (TLS) |
| Usage | Bull queues, Socket.io pub/sub, rate limiting, collaboration state |

### Storage — S3

| Bucket | Purpose | Access |
|--------|---------|--------|
| `outline-static-assets` | Built frontend JS/CSS, fonts, images | CloudFront OAC (no public access) |
| `outline-uploads` | User file uploads, attachments, avatars | Presigned URLs from app (no public access) |

### Secrets — AWS Secrets Manager

Stores: `SECRET_KEY`, `UTILS_SECRET`, `DATABASE_URL`, `REDIS_URL`, auth provider credentials (Google/OIDC/Slack client IDs and secrets). Injected into Fargate tasks at launch.

### DNS — Route 53

| Record | Type | Target |
|--------|------|--------|
| `wiki.example.com` | A (Alias) | CloudFront distribution |

---

## Security Design

| Layer | Mechanism |
|-------|-----------|
| Edge | CloudFront + ACM SSL termination |
| Network | VPC isolation — Fargate in private subnets, data layer unreachable from internet |
| Load Balancer | ALB in public subnets, security group allows only 80/443 from `0.0.0.0/0` |
| Compute → Data | Security groups allow Fargate → RDS (5432) and Fargate → Redis (6379) only |
| Credentials | Secrets Manager, no hardcoded keys. ECS task role for S3 (no access keys) |
| App | `FORCE_HTTPS=false` (ALB handles SSL), `app.proxy=true` trusts `X-Forwarded-Proto` |

### Security Groups

```
sg-alb:         Inbound 80, 443 from 0.0.0.0/0
sg-fargate:     Inbound 3000 from sg-alb only
sg-rds:         Inbound 5432 from sg-fargate only
sg-redis:       Inbound 6379 from sg-fargate only
```

### IAM Roles

| Role | Permissions |
|------|------------|
| ECS Execution Role | Pull from ECR, read Secrets Manager, write CloudWatch Logs |
| ECS Task Role | S3 read/write on uploads bucket (presigned URLs, no access keys needed) |
| GitHub Actions Deploy Role | OIDC federated — push to ECR, update ECS services, sync S3, invalidate CloudFront |

---

## CI/CD — GitHub Actions

```
Push to main
    │
    ▼
┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────────┐
│  Build &  │───▶│ Push to  │───▶│ Run DB       │───▶│ Deploy to    │
│  Test     │    │ ECR      │    │ Migrations   │    │ ECS Fargate  │
└──────────┘    └──────────┘    │ (one-off task)│    │ (rolling)    │
                                └──────────────┘    └──────────────┘
                                                           │
                                                    ┌──────▼───────┐
                                                    │ Sync static  │
                                                    │ assets to S3 │
                                                    │ + invalidate │
                                                    │ CloudFront   │
                                                    └──────────────┘
```

| Step | Action |
|------|--------|
| Build & Test | `yarn install`, `yarn lint`, `yarn tsc`, `yarn test`, `yarn build` |
| Push to ECR | Build Docker image, tag with commit SHA + `latest`, push |
| DB Migrations | Run one-off Fargate task: `yarn db:migrate` (must succeed before deploy) |
| Deploy | Update all 4 ECS services to new image — rolling deployment |
| Static Assets | `aws s3 sync build/app/ s3://outline-static-assets/static/` + CloudFront invalidation |

Authentication via OIDC federation — no stored AWS credentials in GitHub.

---

## Terraform Module Structure

```
terraform/
├── main.tf                 # Root module, wires everything together
├── variables.tf            # Input variables (domain, region, instance sizes)
├── outputs.tf              # VPC ID, ALB DNS, CloudFront domain, RDS endpoint
├── providers.tf            # AWS provider config
├── backends.tf             # S3 + DynamoDB state backend
│
├── modules/
│   ├── vpc/                # VPC, subnets, NAT GWs, route tables, flow logs
│   ├── security-groups/    # All SG definitions and rules
│   ├── acm/                # ACM certificates (us-east-1 for CloudFront + app region)
│   ├── rds/                # PostgreSQL Multi-AZ, parameter group, subnet group
│   ├── elasticache/        # Redis cluster, subnet group
│   ├── s3/                 # Static assets + uploads buckets, policies, CORS
│   ├── ecr/                # Container registry
│   ├── ecs/                # Cluster, task definitions, services, auto-scaling
│   ├── alb/                # ALB, listeners, target groups, rules
│   ├── cloudfront/         # Distribution, OAC, behaviors, cache policies
│   ├── route53/            # DNS records
│   ├── secrets/            # Secrets Manager resources
│   └── iam/                # Execution role, task role, deploy role
│
├── environments/
│   ├── production.tfvars
│   └── staging.tfvars
```

---

## Key Environment Variables for Fargate Tasks

| Variable | Value |
|----------|-------|
| `URL` | `https://wiki.example.com` |
| `PORT` | `3000` |
| `DATABASE_URL` | From Secrets Manager → RDS endpoint |
| `REDIS_URL` | `rediss://outline-redis.xxx.cache.amazonaws.com:6379` |
| `FILE_STORAGE` | `s3` |
| `AWS_REGION` | `us-east-1` (or chosen region) |
| `AWS_S3_UPLOAD_BUCKET_NAME` | `outline-uploads` |
| `CDN_URL` | `https://d1234abcd.cloudfront.net` |
| `FORCE_HTTPS` | `false` (ALB/CloudFront handle SSL) |
| `SECRET_KEY` | From Secrets Manager |
| `UTILS_SECRET` | From Secrets Manager |
| `SERVICES` | Varies per task definition |

---

## Estimated Monthly Cost (Production HA)

| Service | Spec | Estimated Cost |
|---------|------|---------------|
| Fargate (web 2x) | 0.5 vCPU, 1 GB each | ~$30 |
| Fargate (realtime 2x) | 0.5 vCPU, 1 GB each | ~$30 |
| Fargate (worker 1x) | 0.5 vCPU, 1 GB | ~$15 |
| Fargate (cron 1x) | 0.25 vCPU, 0.5 GB | ~$8 |
| RDS PostgreSQL | db.r6g.large Multi-AZ | ~$380 |
| ElastiCache Redis | cache.r6g.large + replica | ~$290 |
| ALB | Standard | ~$25 |
| NAT Gateways (2x) | Per AZ | ~$65 |
| CloudFront | Moderate traffic | ~$20 |
| S3 | Storage + requests | ~$5 |
| Secrets Manager | 10 secrets | ~$4 |
| Route 53 | 1 hosted zone | ~$1 |
| **Total** | | **~$873/mo** |

Staging: Use single-AZ, smaller instances (`db.t4g.medium`, `cache.t4g.medium`), 1 NAT Gateway → ~$200/mo.
