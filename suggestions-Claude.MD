# Outline Architecture Review — Suggestions

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
