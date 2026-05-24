# Health Monitoring & Visualization Plan

> **Origin**: Repository `HDAli00/clouds-outline` (Outline — collaborative wiki/knowledge base)
> **Date**: 2026-05-24
> **Chosen approach**: Option 4 — StatsD Exporter (zero code changes)

---

## Current Instrumentation State

Outline already emits metrics and traces via **Datadog** tooling:

| Layer | Tool | Env Var to Enable |
|-------|------|-------------------|
| APM / Distributed Tracing | `dd-trace` | `DD_API_KEY` |
| Custom Metrics | `hot-shots` (StatsD) | Always active (silent on failure) |
| Error Tracking | `@sentry/node` | `SENTRY_DSN` |

### Metrics Already Being Emitted

The app emits these StatsD metrics with the `outline.` prefix:

**HTTP & Connections:**
- `outline.connections.count` — active HTTP connections per instance
- `outline.rate_limit.exceeded` — rate limit hits (tagged by endpoint)

**WebSockets:**
- `outline.websockets.count` — active WebSocket connections per instance
- `outline.websockets.connected` — new connection events
- `outline.websockets.disconnected` — disconnection events

**Collaboration (Y.js):**
- `outline.collaboration.connections_count` — active collab connections per instance
- `outline.collaboration.documents_count` — documents being actively edited per instance
- `outline.collaboration.load_document` — document load events
- `outline.collaboration.connect` — new collab connections
- `outline.collaboration.disconnect` — collab disconnections
- `outline.collaboration.change` — document change events
- `outline.collaboration.authentication_failed` — auth failures

**Job Queues (Bull):**
- `outline.<queue>.count` — pending jobs in queue
- `outline.<queue>.delayed_count` — delayed jobs
- `outline.<queue>.jobs.completed` — successful job completions
- `outline.<queue>.jobs.errored` — job errors
- `outline.<queue>.jobs.failed` — permanent job failures
- `outline.<queue>.jobs.stalled` — stalled jobs

**Logging:**
- `outline.logger.warning` — warning log count
- `outline.logger.error` — error log count (tagged by type)

---

## Option 4: StatsD Exporter (Chosen)

**Zero code changes required.** Deploy the Prometheus `statsd_exporter` as a sidecar or standalone service to translate StatsD metrics into Prometheus format.

### Architecture

```
┌─────────────────────┐         ┌──────────────────────┐
│  Outline App        │         │  statsd_exporter     │
│                     │  UDP    │                      │
│  hot-shots ─────────┼────────▶│  :9125 (StatsD in)   │
│  (StatsD client)    │         │  :9102 (Prometheus)  │
│                     │         │                      │
└─────────────────────┘         └──────────┬───────────┘
                                           │
                                    ┌──────▼───────┐
                                    │  Prometheus  │
                                    │  (scrape)    │
                                    └──────┬───────┘
                                           │
                                    ┌──────▼───────┐
                                    │   Grafana    │
                                    │  (visualize) │
                                    └──────────────┘
```

### Deployment (Fargate Sidecar)

Add `statsd_exporter` as a sidecar container in each Fargate task definition:

```json
{
  "name": "statsd-exporter",
  "image": "prom/statsd-exporter:v0.26.0",
  "portMappings": [
    { "containerPort": 9125, "protocol": "udp" },
    { "containerPort": 9102, "protocol": "tcp" }
  ],
  "command": [
    "--statsd.listen-udp=:9125",
    "--web.listen-address=:9102",
    "--statsd.mapping-config=/etc/statsd/mapping.yml"
  ],
  "essential": false,
  "cpu": 64,
  "memory": 128
}
```

### StatsD Mapping Configuration

Create `mapping.yml` to translate Outline's metric names into clean Prometheus metrics:

```yaml
mappings:
  # HTTP connections
  - match: "outline.connections.count"
    name: "outline_http_connections_active"
    labels:
      instance: "$1"

  # WebSockets
  - match: "outline.websockets.count"
    name: "outline_websockets_connections_active"
  - match: "outline.websockets.connected"
    name: "outline_websockets_connections_total"
  - match: "outline.websockets.disconnected"
    name: "outline_websockets_disconnections_total"

  # Collaboration
  - match: "outline.collaboration.connections_count"
    name: "outline_collaboration_connections_active"
  - match: "outline.collaboration.documents_count"
    name: "outline_collaboration_documents_active"
  - match: "outline.collaboration.connect"
    name: "outline_collaboration_connections_total"
  - match: "outline.collaboration.disconnect"
    name: "outline_collaboration_disconnections_total"
  - match: "outline.collaboration.change"
    name: "outline_collaboration_changes_total"
  - match: "outline.collaboration.load_document"
    name: "outline_collaboration_document_loads_total"
  - match: "outline.collaboration.authentication_failed"
    name: "outline_collaboration_auth_failures_total"

  # Job queues
  - match: "outline.*.count"
    name: "outline_queue_pending_jobs"
    labels:
      queue: "$1"
  - match: "outline.*.delayed_count"
    name: "outline_queue_delayed_jobs"
    labels:
      queue: "$1"
  - match: "outline.*.jobs.completed"
    name: "outline_queue_jobs_completed_total"
    labels:
      queue: "$1"
  - match: "outline.*.jobs.errored"
    name: "outline_queue_jobs_errored_total"
    labels:
      queue: "$1"
  - match: "outline.*.jobs.failed"
    name: "outline_queue_jobs_failed_total"
    labels:
      queue: "$1"
  - match: "outline.*.jobs.stalled"
    name: "outline_queue_jobs_stalled_total"
    labels:
      queue: "$1"

  # Rate limiting
  - match: "outline.rate_limit.exceeded"
    name: "outline_rate_limit_exceeded_total"

  # Logging
  - match: "outline.logger.warning"
    name: "outline_log_warnings_total"
  - match: "outline.logger.error"
    name: "outline_log_errors_total"
```

### Environment Variable (Point App at Sidecar)

The `hot-shots` StatsD client in Outline defaults to `localhost:8125`. The sidecar listens on `127.0.0.1:9125` within the same Fargate task network namespace:

```
DD_AGENT_HOST=127.0.0.1
DD_DOGSTATSD_PORT=9125
```

### Prometheus Scrape Config

```yaml
scrape_configs:
  - job_name: 'outline'
    ecs_sd_configs:
      - region: us-east-1
    relabel_configs:
      - source_labels: [__meta_ecs_container_name]
        regex: statsd-exporter
        action: keep
      - source_labels: [__meta_ecs_task_definition_family]
        target_label: service
    metrics_path: /metrics
    scrape_interval: 15s
```

Alternatively, use **Amazon Managed Prometheus (AMP)** with the ECS Prometheus scraper.

### Grafana Dashboard Panels

**Overview Row:**
- Active HTTP connections (`outline_http_connections_active`)
- Active WebSocket connections (`outline_websockets_connections_active`)
- Active collaboration sessions (`outline_collaboration_connections_active`)
- Documents being edited (`outline_collaboration_documents_active`)

**Queue Health Row:**
- Pending jobs per queue (`outline_queue_pending_jobs`)
- Job completion rate (`rate(outline_queue_jobs_completed_total[5m])`)
- Job error rate (`rate(outline_queue_jobs_errored_total[5m])`)
- Stalled jobs (`outline_queue_jobs_stalled_total`)

**Error Row:**
- Rate limit hits (`rate(outline_rate_limit_exceeded_total[5m])`)
- Application errors (`rate(outline_log_errors_total[5m])`)
- Collaboration auth failures (`rate(outline_collaboration_auth_failures_total[5m])`)

### Alerting Rules

```yaml
groups:
  - name: outline
    rules:
      - alert: HighQueueDepth
        expr: outline_queue_pending_jobs > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Queue {{ $labels.queue }} has {{ $value }} pending jobs"

      - alert: JobFailureSpike
        expr: rate(outline_queue_jobs_failed_total[5m]) > 0.1
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Job failures spiking on queue {{ $labels.queue }}"

      - alert: CollaborationAuthFailures
        expr: rate(outline_collaboration_auth_failures_total[5m]) > 1
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "Collaboration authentication failures detected"

      - alert: RateLimitExceeded
        expr: rate(outline_rate_limit_exceeded_total[5m]) > 10
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "High rate of rate-limited requests"
```

### Pros & Cons

| Pros | Cons |
|------|------|
| Zero code changes | Extra sidecar per task (~64MB RAM) |
| Immediate access to all existing metrics | No request-level traces (only aggregate metrics) |
| Works with any Prometheus-compatible backend | StatsD mapping requires maintenance as new metrics are added |
| Simple rollback (just remove sidecar) | UDP transport means metrics can be lost under load |
| Production-proven pattern | No distributed tracing visualization |

---

## Option 1: Replace StatsD with Prometheus Client (Code Change)

Replace the `hot-shots` StatsD client with `prom-client` and expose a `/metrics` endpoint directly from the Outline app.

### Architecture

```
┌─────────────────────────────┐
│  Outline App                │
│                             │
│  prom-client ──▶ /metrics   │◀─── Prometheus scrapes directly
│  (native Prometheus)        │
│                             │
└─────────────────────────────┘
         │
  ┌──────▼───────┐
  │  Prometheus  │
  └──────┬───────┘
         │
  ┌──────▼───────┐
  │   Grafana    │
  └──────────────┘
```

### Implementation

**1. Replace `server/logging/Metrics.ts`:**

```typescript
import { Counter, Gauge, Registry, collectDefaultMetrics } from "prom-client";

const register = new Registry();
collectDefaultMetrics({ register, prefix: "outline_" });

class Metrics {
  private counters = new Map<string, Counter>();
  private gauges = new Map<string, Gauge>();

  private getCounter(name: string, labelNames?: string[]): Counter {
    const key = name;
    if (!this.counters.has(key)) {
      const counter = new Counter({
        name: `outline_${name.replace(/\./g, "_")}_total`,
        help: `Counter for ${name}`,
        labelNames: labelNames || [],
        registers: [register],
      });
      this.counters.set(key, counter);
    }
    return this.counters.get(key)!;
  }

  private getGauge(name: string): Gauge {
    if (!this.gauges.has(name)) {
      const gauge = new Gauge({
        name: `outline_${name.replace(/\./g, "_")}`,
        help: `Gauge for ${name}`,
        labelNames: ["instance"],
        registers: [register],
      });
      this.gauges.set(name, gauge);
    }
    return this.gauges.get(name)!;
  }

  gauge(key: string, value: number): void {
    this.getGauge(key).set(value);
  }

  gaugePerInstance(key: string, value: number): void {
    const instanceId = process.env.INSTANCE_ID || process.pid.toString();
    this.getGauge(key).set({ instance: instanceId }, value);
  }

  increment(key: string, tags?: Record<string, string>): void {
    this.getCounter(key, tags ? Object.keys(tags) : []).inc(tags || {});
  }

  async flush(): Promise<void> {
    // No-op for Prometheus (pull-based)
  }

  getRegister(): Registry {
    return register;
  }
}

export default new Metrics();
```

**2. Add `/metrics` endpoint:**

```typescript
router.get("/metrics", async (ctx) => {
  ctx.set("Content-Type", Metrics.getRegister().contentType);
  ctx.body = await Metrics.getRegister().metrics();
});
```

**3. Swap dependencies:**
```bash
yarn remove hot-shots
yarn add prom-client
```

### Pros & Cons

| Pros | Cons |
|------|------|
| No sidecar needed | Code change required |
| Native Prometheus format (no mapping) | Must maintain prom-client registry |
| Node.js runtime metrics (GC, event loop, heap) for free | Risk of metric cardinality explosion if labels not controlled |
| Prometheus scrapes directly — no UDP loss | `/metrics` endpoint needs rate limiting or auth |
| New metrics automatically available | Breaking change for anyone using Datadog |

### Estimated Effort
- 1-2 days implementation
- Replace `Metrics.ts` (1 file), add `/metrics` route (1 line), update deps
- Test all existing metric call sites still work

---

## Option 3: Datadog Agent OTLP Forwarding

Keep the existing Datadog instrumentation (`dd-trace` + `hot-shots`) but configure the **Datadog Agent** to forward data in OTLP format to an OpenTelemetry Collector, which exports to Grafana's stack.

### Architecture

```
┌───────────────────┐      ┌─────────────────────┐      ┌──────────────────┐
│  Outline App      │      │  Datadog Agent      │      │  OTel Collector  │
│                   │      │                     │      │                  │
│  dd-trace ────────┼─────▶│  APM intake         │      │                  │
│  hot-shots ───────┼─────▶│  StatsD intake      │──────▶  OTLP exporter  │
│                   │      │                     │      │                  │
└───────────────────┘      │  otlp_config:       │      └────────┬─────────┘
                           │    endpoint: otel   │               │
                           └─────────────────────┘       ┌───────▼────────┐
                                                         │  Grafana Stack │
                                                         │                │
                                                         │  Tempo (traces)│
                                                         │  Mimir (metrics│
                                                         │  Loki (logs)   │
                                                         └────────────────┘
```

### Datadog Agent Configuration

```yaml
# datadog.yaml
apm_config:
  enabled: true

otlp_config:
  traces:
    enabled: true
    endpoint: "otel-collector:4317"
  metrics:
    enabled: true
    endpoint: "otel-collector:4317"
```

### OpenTelemetry Collector Configuration

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317

processors:
  batch:
    timeout: 5s
    send_batch_size: 1000

exporters:
  prometheusremotewrite:
    endpoint: "https://mimir.example.com/api/v1/push"
    headers:
      X-Scope-OrgID: outline

  otlp/tempo:
    endpoint: "tempo.example.com:4317"
    tls:
      insecure: false

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheusremotewrite]
```

### AWS Deployment (Fargate Sidecar)

```json
{
  "name": "datadog-agent",
  "image": "datadog/agent:latest",
  "portMappings": [
    { "containerPort": 8126, "protocol": "tcp" },
    { "containerPort": 8125, "protocol": "udp" }
  ],
  "environment": [
    { "name": "DD_API_KEY", "value": "<from-secrets-manager>" },
    { "name": "DD_APM_ENABLED", "value": "true" },
    { "name": "DD_OTLP_CONFIG_TRACES_ENABLED", "value": "true" },
    { "name": "DD_OTLP_CONFIG_METRICS_ENABLED", "value": "true" },
    { "name": "DD_OTLP_GRPC_ENDPOINT", "value": "otel-collector:4317" }
  ],
  "essential": false,
  "cpu": 128,
  "memory": 256
}
```

### Pros & Cons

| Pros | Cons |
|------|------|
| Zero code changes | Requires Datadog Agent license (DD_API_KEY) |
| Full distributed traces in Grafana Tempo | Most complex setup (3 components: app + DD agent + OTel Collector) |
| Preserves existing Datadog dashboards | Higher resource cost (DD agent ~256MB + OTel Collector) |
| Rich APM data (request traces, DB queries, Redis calls) | Datadog agent is heavyweight for just forwarding |
| Both Datadog AND Grafana can run simultaneously | OTLP forwarding is newer DD feature — less battle-tested |

### When to Choose This
- You already have a Datadog license and want to keep it
- You need distributed tracing (not just aggregate metrics)
- You want to gradually migrate from Datadog to Grafana without disruption

---

## Comparison Summary

| | Option 4: StatsD Exporter | Option 1: prom-client | Option 3: DD Agent OTLP |
|---|---|---|---|
| **Code changes** | None | Yes (1 file + 1 route) | None |
| **Sidecar resources** | 64 MB | None | 256+ MB |
| **Distributed tracing** | No | No | Yes |
| **Node.js runtime metrics** | No | Yes (free with prom-client) | Yes (via DD agent) |
| **Setup complexity** | Low | Low-Medium | High |
| **Monthly cost** | ~$0 (just CPU/RAM) | ~$0 | Datadog license |
| **Migration risk** | Zero | Low (same interface) | Low |
| **Best for** | Quick win, metrics only | Long-term clean architecture | Full observability with traces |

---

## Recommended Grafana Stack (AWS)

| Component | AWS Managed Option | Self-Hosted Option |
|-----------|-------------------|-------------------|
| Metrics storage | Amazon Managed Prometheus (AMP) | Prometheus / Mimir |
| Visualization | Amazon Managed Grafana (AMG) | Grafana OSS |
| Alerting | Grafana Alerting -> SNS | Alertmanager |
| Traces (if Option 3) | AWS X-Ray or Grafana Tempo | Tempo |

---

## Implementation Checklist (Option 4)

- [ ] Add `statsd_exporter` to Fargate task definitions (web, realtime, worker, cron)
- [ ] Create `mapping.yml` ConfigMap/S3 file with metric translations
- [ ] Configure StatsD port (`9125`) in Outline env or keep default `8125`
- [ ] Set up Prometheus (AMP or self-hosted) with ECS service discovery
- [ ] Create Grafana data source pointing to Prometheus
- [ ] Build dashboard with panels for connections, queues, collaboration, errors
- [ ] Configure alerting rules for queue depth, job failures, rate limits
- [ ] Test: verify metrics flow end-to-end in staging before production
