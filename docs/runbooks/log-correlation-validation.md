# Runbook: validate logs ↔ metrics ↔ traces correlation

Validates that the microservices emit **business logs carrying `trace_id`** and
that all correlation directions resolve in Grafana, after enabling DEBUG on the
apps' base package.

## Background

- Log levels are governed entirely by the `microservices-logback` ConfigMap in the
  GitOps repo (`nubenetes/jenkins-2026-gitops-config`,
  `helm/microservices/templates/logback-configmap.yaml`): the Deployment sets
  `LOGGING_CONFIG=/etc/logback/logback.xml`, which **replaces** JHipster's own
  `logback-spring.xml`. Root is `INFO`; 7 noisy framework loggers are pinned to
  `WARN`.
- To surface in-span business logs we set `io.github.jhipster.sample` to `DEBUG`
  (gitops PR #2). Both apps (`gateway`, `jhipstersamplemicroservice`) share that
  base package and ship an AOP `LoggingAspect` that logs `@Service` /
  `@RestController` method enter/exit at DEBUG **inside the request span**, so the
  lines carry the agent-injected `trace_id`/`span_id`.
- Mode-independent: this ConfigMap applies unchanged across all `observability.mode`
  backends; only the downstream log store differs (Loki / Grafana Cloud Loki /
  Azure Log Analytics / AWS CloudWatch). The Grafana step below assumes the live
  cluster is on `observability.mode=oss` (in-cluster Grafana/Loki/Tempo).

> ⚠️ Only **step 3** mutates the cluster (a rollout restart). Everything else is
> read-only inspection or traffic generation.

## 0. Context

```bash
NS=microservices                 # stable env namespace
APP=microservices-stable         # ArgoCD application (appset: microservices-{env})
CM=microservices-logback         # the ConfigMap that sets log levels
kubectl config current-context   # sanity: confirm you're on the live GKE cluster
```

## 1. Land the change — sync ArgoCD

Auto-sync may already have applied it; force it to be sure.

```bash
argocd app get  "$APP"           # check Sync / Health status
argocd app sync "$APP"           # pulls the updated ConfigMap
# or, without the argocd CLI:
kubectl -n argocd annotate app "$APP" argocd.argoproj.io/refresh=hard --overwrite
```

## 2. Verify the ConfigMap carries the DEBUG logger

```bash
kubectl -n "$NS" get configmap "$CM" -o jsonpath='{.data.logback\.xml}' \
  | grep -n 'io.github.jhipster.sample'
# Expect: <logger name="io.github.jhipster.sample" level="DEBUG"/>
# If absent, ArgoCD hasn't synced yet — re-run step 1.
```

## 3. ⚠️ Restart pods so they re-read the ConfigMap

`LOGGING_CONFIG` is read at JVM start, so a ConfigMap change alone does **not**
reload — a rollout restart is required.

```bash
kubectl -n "$NS" rollout restart deploy/gateway deploy/jhipstersamplemicroservice
kubectl -n "$NS" rollout status  deploy/gateway --timeout=180s
kubectl -n "$NS" rollout status  deploy/jhipstersamplemicroservice --timeout=180s
```

### 3b. Re-confirm the OTel javaagent attached (known race on fresh pods)

If `JAVA_TOOL_OPTIONS` lacks `-javaagent`, the auto-instrumentation CR / Deployment
race lost — restart again.

```bash
kubectl -n "$NS" get pod -l app.kubernetes.io/name=gateway \
  -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="JAVA_TOOL_OPTIONS")].value}{"\n"}'
# Expect a value containing: -javaagent:/otel-auto-instrumentation/...
```

## 4. Generate traffic

Logs only get a `trace_id` when emitted **inside a request span**, so idle
services produce nothing to correlate.

```bash
# Preferred: the in-cluster k6 smoke run of whichever CI engine (ci.engine) is
# deployed — Jenkins (job microservices-k6-smoke) · Tekton / Argo Workflows
# (the microservices-k6-smoke PipelineRun/Workflow) · GitHub Actions
# (Day2.traffic.01-k6). All hit the gateway via service DNS.
# Or port-forward + curl a business endpoint the AOP LoggingAspect wraps:
kubectl -n "$NS" port-forward svc/gateway 8080:8080 >/dev/null 2>&1 &
curl -s localhost:8080/management/health
curl -s 'localhost:8080/services/jhipstersamplemicroservice/api/...'   # any @RestController route
```

## 5. Pod-level proof: DEBUG lines carry `trace_id`

```bash
kubectl -n "$NS" logs deploy/gateway --since=2m \
  | grep -iE 'jhipster|trace_id' | head
# Expect ECS-JSON lines with "log.level":"DEBUG", a business "message",
# and a populated "trace_id"/"span_id".
```

## 6. Grafana — prove both correlation directions

In-cluster Grafana at `https://grafana.jenkins2026.nubenetes.com` (Google SSO via
IAP):

- **traces → logs**: `microservices-overview` → a `gateway` trace → **"Logs for
  this span"** (Tempo `tracesToLogsV2`). The DEBUG business lines appear.
- **logs → traces**: Explore on the **Loki** datasource,
  `{k8s_namespace_name="microservices", service_name="gateway"} | json` → click a
  line's `trace_id` derived field → resolves the trace in **Tempo**.
- **metrics → traces (exemplars)**: on an
  `http_server_request_duration_seconds_bucket{service_name="gateway"}` panel, an
  exemplar dot's `trace_id` opens the trace. (Requires Prometheus
  `exemplar-storage`, enabled in PR #177.)

## Rollback

If DEBUG volume is too costly for the log backend, revert the gitops
`microservices-logback` logger to `INFO` (or delete the line) → ArgoCD sync →
rollout restart (step 3).

## Gotchas (why panels can look empty without anything being broken)

- **No traffic** → no in-span logs (step 4 is mandatory).
- **OTel javaagent injection race** on fresh pods → no traces at all until a
  restart (step 3b).
- **Idle JVM GC** → *GC Pause p99* panel returns `NaN`; run load to populate it.
