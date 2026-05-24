# Claude Readme Suggestions

> **Origin**: Repository `HDAli00/clouds-outline` (Outline — collaborative wiki/knowledge base)
> **Date**: 2026-05-24
> **Branch reviewed**: `claude/notion-app-review-ifZE0` (now deleted)

This file consolidates two review documents produced during an architecture review of the Outline application.

---

# Part 1 — Architecture Review Suggestions

> Originally: `suggestions-Claude.MD` in `HDAli00/clouds-outline`

## Architecture Strengths

### 1. Clean Monorepo Separation
- Well-defined boundaries: `app/` (frontend), `server/` (backend), `shared/` (common), `plugins/` (extensions)
- No circular dependencies between layers — shared code is truly platform-agnostic
- Command pattern for cross-model business logic (18 commands with proper transactions)
- Presenter layer cleanly separates DB models from API responses

### 2. Strong Plugin Architecture
- 8 hook types (AuthProvider, API, SearchProvider, UnfurlProvider, Processor, Task, EmailTemplate, GroupSyncProvider)
- Type-safe registration with `PluginValueMap`, priority-based execution (VeryHigh=0 to VeryLow=500)
- Plugins are self-contained with server/client code, env config, and metadata
- Plugin API routes mounted before built-in routes, allowing overrides
- 22 built-in plugins covering auth, integrations, analytics, storage, and search

### 3. Robust Real-Time Collaboration
- Y.js CRDT-based editing via Hocuspocus with 6 collaboration extensions
- Double-checked locking pattern for Y.js state initialization
- Database UPDATE locks prevent race conditions on concurrent state access
- WebSocket layer for metadata sync (documents, presence, notifications)

### 4. Solid Security Posture
- Three auth methods: OAuth tokens, API keys, session JWT — each with proper validation
- 22/40+ API routes have rate limiting (Redis-backed)
- Schema-based request validation on all endpoints
- cancan-based authorization with declarative abilities and policy serialization for UI
- CSRF, Helmet headers, CSP, encrypted secrets
- API keys rejected in cookies, Bearer token preferred

### 5. Scalable Backend Infrastructure
- 6 independently deployable services (web, API, WebSocket, collaboration, worker, cron)
- Graceful shutdown with ordered execution and timeouts (ShutdownHelper)
- Health check endpoint verifying both DB and Redis
- Bull job queue with 30+ processors and 70+ async tasks
- AsyncLocalStorage for request-scoped context

### 6. Good Test Infrastructure
- Vitest multi-environment setup (Node + JSDOM)
- Comprehensive factory functions (buildUser, buildTeam, buildDocument, etc.)
- MSW for external service mocking
- Parallel test execution enabled
- 211 test files with co-located test pattern

### 7. Consistent API Patterns
- Middleware ordering: `rateLimiter -> auth -> validate -> transaction`
- All mutations wrapped in transactions
- Clear `authorize(user, "action", resource)` pattern
- Validation via schema at route definition

---

## Weaknesses & Risks

### Critical

#### 1. Plugin Loading Has No Error Isolation
- **Location**: `server/utils/PluginManager.ts:144-148`
- `require()` calls with NO try-catch — a single malformed plugin crashes the entire server
- No plugin validation or health checks before registration
- No tests for PluginManager (154 LOC completely untested)
- **Recommendation**: Wrap each plugin `require()` in try-catch, log errors, skip broken plugins

#### 2. documentPermanentDeleter — O(n*m) Query Performance
- **Location**: `server/commands/documentPermanentDeleter.ts`
- Issues a raw SQL full-text search query per attachment per document during deletion
- 100+ attachments = 100+ sequential queries with no batching
- **Recommendation**: Batch attachment lookup with a single `WHERE id IN (...)` query

#### 3. N+1 Query Risks in Document Loading
- **Location**: `server/models/Document.ts` (withMembership scope, lines 179-234)
- `separate: true` on multiple associations triggers extra queries per document
- Nested include chain: Document -> Collections -> Group -> GroupUser
- Presenter layer maps with `Promise.all(results.map(...))`, potentially adding DB calls per doc
- **Recommendation**: Eager load with explicit `include`, add query logging in development

### High

#### 4. WebSocket Subscription Leaks
- **Location**: `app/components/WebsocketProvider.tsx`
- 12 socket.on() handlers registered during effects, cleanup only removes visibility listener
- Handlers accumulate on reconnection without unsubscription
- **Recommendation**: Return cleanup functions from useEffect calling socket.off() for each handler

#### 5. God Object Stores
- **Location**: `app/stores/DocumentsStore.ts` (~19KB), `app/stores/UiStore.ts` (~12KB)
- DocumentsStore: 20+ methods covering fetch, search, move, duplicate, import, archive, delete
- UiStore: 20+ unrelated UI concerns (sidebar, theme, presentation, active models)
- 11+ rootStore cross-references creating tight coupling
- **Recommendation**: Split into focused sub-stores (DocumentSearchStore, SidebarStore, ThemeStore)

#### 6. Missing Component-Level Error Boundaries
- **Location**: `app/components/ErrorBoundary.tsx`
- Only top-level ErrorBoundary — one component crash kills the entire app
- No graceful degradation to read-only mode
- **Recommendation**: Add error boundaries around editor, sidebar, comments, settings sections

#### 7. Missing Database Indexes
- **Location**: Various models
- No composite indexes on hot paths: `(userId, teamId)`, `(collectionId, publishedAt)`, `(parentDocumentId, index)`
- **Recommendation**: Add migration with indexes on frequently queried composite keys

#### 8. Large Untested Authorization Surface
- **Location**: `server/policies/`
- 3,004 LOC of authorization code with only 5 test files
- Core `cancan.ts` (260 LOC) has NO tests
- Most resource types untested (Integration, ApiKey, Share, etc.)
- **Recommendation**: Add policy tests for all resource types, especially cancan core logic

### Medium

#### 9. Y.js Collaboration Untested
- **Location**: `server/collaboration/`
- PersistenceExtension (145 LOC) — no tests
- Y.js state merging and conflict resolution untested
- Document has THREE representations (content, text, state) with unclear migration path
- Redis as single point of failure for collaborator tracking
- **Recommendation**: Add integration tests for concurrent edit scenarios

#### 10. AfterCreate Hook Transaction Isolation
- **Location**: `server/models/Document.ts:478-496`
- @AfterCreate hook creates separate transaction from request transaction
- Hook failures won't roll back parent — can leave orphaned documents
- **Recommendation**: Pass parent transaction to hooks

#### 11. No Optimistic Update Rollback
- **Location**: `app/stores/DocumentsStore.ts`
- Move/archive/delete operations don't rollback on server rejection
- **Recommendation**: Capture state before mutation, restore on failure

#### 12. Permission Revocation Not Handled
- **Location**: `app/components/WebsocketProvider.tsx`
- Document removed from store on permission loss, but component doesn't redirect
- **Recommendation**: Listen for store removals and redirect to home

#### 13. CSRF After Body Parser
- **Location**: `server/routes/api/index.ts:81`
- verifyCSRFToken runs after body parsing — multipart forms processed before CSRF check
- **Recommendation**: Move CSRF verification before body parser

#### 14. Missing Plugin Lifecycle Management
- No `onInit`, `onUnload`, `onDisable` hooks for plugins
- GitHub uninstall hook exists but is ad-hoc, not standardized
- No cleanup mechanism when plugins fail or are disabled
- **Recommendation**: Add standardized lifecycle hooks to plugin interface

### Low

#### 15. Observer Performance
- 242 @observer components without precise computed selectors
- Possible unnecessary re-renders during real-time collaboration
- **Recommendation**: Profile before optimizing; add selectors in hot paths

#### 16. Hardcoded Task Configs
- **Location**: `server/queues/tasks/` (CleanupOldImportsTask, CleanupOldEventsTask, ErrorTimedOutImportsTask)
- **Recommendation**: Extract to environment variables or team settings

#### 17. Pin Count Race Condition
- **Location**: `server/commands/pinCreator.ts:43`
- Count-then-insert gap allows exceeding limits under concurrency
- **Recommendation**: Use DB constraint or SELECT FOR UPDATE

---

## Test Coverage Gaps

| Area | LOC | Tests | Risk |
|------|-----|-------|------|
| PluginManager | 154 | 0 | App crash from bad plugin |
| cancan.ts (core auth) | 260 | 0 | Authorization bypass |
| PersistenceExtension (Y.js) | 145 | 0 | Data loss on concurrent edits |
| Most policies (Integration, ApiKey, Share, etc.) | ~2000 | 0 | Permission errors |
| GitHub webhook handling | ~300 | 0 | Malformed payload crashes |

---

## Known Technical Debt

| Location | Issue |
|----------|-------|
| `server/presenters/unfurl.ts:38` | Backwards compatibility to remove |
| `server/presenters/revision.ts:8` | Fallback to remove after migrations |
| `server/policies/document.ts:53` | Separate commenting permission needed |
| `server/models/AuthenticationProvider.ts:30` | Hardcoded plugin references |
| `server/storage/files/BaseStorage.ts:32` | S3 logic needs abstracting |
| `server/routes/api/groups/groups.ts:167` | Deprecated endpoint to remove |

---

## Prioritized Recommendations

### Quick Wins (1-2 days each)
1. Wrap plugin loading in try-catch — prevents production crashes from bad plugins
2. Batch queries in documentPermanentDeleter — prevents perf issues on bulk delete
3. Fix WebSocket handler cleanup — prevents memory leaks
4. Add composite database indexes — improves query performance
5. Move CSRF before body parser — security fix

### Medium Effort (3-5 days each)
6. Add section-level error boundaries — major UX reliability improvement
7. Add PluginManager and cancan tests — covers highest-risk untested code
8. Add optimistic update rollback — prevents stale state after network errors
9. Handle permission revocation gracefully — redirect users on access loss
10. Extract hardcoded task configs — operational flexibility

### Larger Refactors (1-2 weeks each)
11. Split god object stores — improves maintainability and testability
12. Add Y.js collaboration tests — covers concurrent edit scenarios
13. Add plugin lifecycle hooks — standardized init/cleanup/disable
14. Add query logging/monitoring — catch N+1 issues systematically
15. Expand policy test coverage — all resource types

---

## Overall Assessment

This is a well-engineered production application. The plugin system design is elegant, the command pattern is clean, security coverage is thorough (multi-method auth, rate limiting, CSRF, CSP), and the real-time collaboration stack is a solid architectural choice. The monorepo structure keeps layers aligned without excessive coupling, and the shared code layer has no circular dependencies.

The most critical issues are plugin error isolation (app crash risk), query performance in document deletion, and test coverage gaps in authorization and collaboration. None require fundamental redesign — they are evolutionary debt typical of a mature, actively developed codebase. The highest-ROI fixes are the plugin try-catch wrapper, batch query optimization, and WebSocket cleanup.

---
---

# Part 2 — AWS Deployment Plan

> Originally: `aws-deployment-plan.MD` in `HDAli00/clouds-outline`

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
| Compute -> Data | Security groups allow Fargate -> RDS (5432) and Fargate -> Redis (6379) only |
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
| `DATABASE_URL` | From Secrets Manager -> RDS endpoint |
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

Staging: Use single-AZ, smaller instances (`db.t4g.medium`, `cache.t4g.medium`), 1 NAT Gateway -> ~$200/mo.
