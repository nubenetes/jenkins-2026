# Pipelines as Code

Everything Jenkins-side is defined in this repository - security, the global
shared library, the OpenTelemetry exporter, and the Microservices pipelines (the
stable jobs `gateway`, `jhipstersamplemicroservice` + `microservices-k6-smoke` at the root) - and applied via
**Configuration as Code (JCasC)** + the **Job DSL** plugin. Nothing is
configured by hand in the Jenkins UI.

## JCasC fragments ([`jenkins/casc/`](../jenkins/casc/))

`scripts/04-jenkins.sh` installs the jenkinsci/helm-charts `jenkins` chart
with three JCasC fragments passed via `--set-file`:

| File | Purpose |
|---|---|
| [`jcasc-base.yaml`](../jenkins/casc/jcasc-base.yaml) | Security realm (OIDC with Google, escape-hatch `admin` password from the `jenkins-credentials` Secret), Role-Based Authorization Strategy (`admin` global role; `developer` global role), system message, **global pipeline library** `microservices-shared-library`, and credentials (`container-registry`, `microservices-git`). |
| [`jcasc-otel.yaml`](../jenkins/casc/jcasc-otel.yaml) | Configures the `opentelemetry` plugin's global exporter - OTLP/gRPC to `otel-collector-gateway.observability.svc.cluster.local:4317`. |
| [`jcasc-seed-job.yaml`](../jenkins/casc/jcasc-seed-job.yaml) | Defines the main `seed-jobs` pipeline job that tracks `${JENKINS2026_REPO_BRANCH:-main}` to generate the stable pipelines. |

## Global shared library ([`vars/`](../vars/), [`resources/`](../resources/))

Four steps used by every per-service pipeline: `microservicesBuild`,
`microservicesImage`, `microservicesDeploy`, and `microservicesSmokeTest`. They handle
everything from Maven/NPM builds to Helm deployments and OTel-instrumented
smoke tests. A fifth step, `microservicesK6Smoke`, is used only by the
`microservices-k6-smoke` job - see
[k6 observability smoke test](observability.md#k6-observability-smoke-test).

## The seed job ([`jenkins/pipelines/seed/`](../jenkins/pipelines/seed/))

`seed_jobs.groovy` reads [`services.yaml`](../jenkins/pipelines/seed/services.yaml) to generate the stable pipeline jobs at the root.

### Pipeline Branch & Environment Mapping

Instead of separating stable and development pipelines into separate jobs and folders, a single set of root stable pipelines is generated. These pipelines are dynamically seeded and configured to target the stable environment:

*   **Target Namespace:** `microservices`
*   **Environment Name:** `stable` (modifies `values-stable.yaml` in the GitOps config repository on the `main` branch)

## Pipeline stages ([`Jenkinsfile.microservices`](../jenkins/pipelines/Jenkinsfile.microservices))

1. **Checkout jenkins-2026** (Helm chart + shared lib resources).
2. **Checkout Microservices source** (into `./microservices-src`).
3. **Build & Test** (`microservicesBuild`).
4. **Build & Push Image** (`microservicesImage`).
5. **Deploy to Kubernetes** (`microservicesDeploy`).
6. **Smoke Test** (`microservicesSmokeTest`).

## k6 observability smoke test (`microservices-k6-smoke`)

`seed_jobs.groovy` also generates one extra job `microservices-k6-smoke` at the root (running [`Jenkinsfile.microservices-k6-smoke`](../jenkins/pipelines/Jenkinsfile.microservices-k6-smoke)) that sends synthetic traffic to test Grafana Cloud telemetry correlation.
See [`docs/observability.md`](observability.md#k6-observability-smoke-test) for what it does and why.
