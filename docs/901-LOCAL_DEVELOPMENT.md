[← Previous: 601. DevSecOps](./601-DEVSECOPS.md) | [🏠 Home](../README.md) | [→ Next: 902. Troubleshooting](./902-TROUBLESHOOTING.md)

---

# 901. Local Development

## Prerequisites

- An existing GKE Kubernetes cluster and a `kubectl` context pointing at it. **This repo provisions no cluster infrastructure** (except via `test/e2e.sh`).
- `kubectl`, `helm` (v3), [`yq`](https://github.com/mikefarah/yq) (Go version, `mikefarah/yq`), `git`, `bash`. `gh` (GitHub CLI) only if you plan to push this repo yourself.
- Cluster permissions to create namespaces, RBAC, CRDs (OpenTelemetry Operator) and the workloads described in [201. Architecture](./201-ARCHITECTURE.md).
- A container registry you can push to (default: `ghcr.io/nubenetes/jenkins-2026-microservices` — works anonymously for pulls; pushing needs a token with `write:packages`).
- **ArgoCD OIDC Redirect URI**: To use Google OIDC with ArgoCD, you MUST add `https://argocd.<baseDomain>/api/dex/callback` to your Google OAuth client's **Authorized redirect URIs**.
- (default observability mode) A [Grafana Cloud](https://grafana.com/products/cloud/) stack (free tier is enough) for its OTLP gateway endpoint + API key.

## Quick Start

```bash
# 1. Review/edit config/config.yaml - observability.mode (grafana-cloud|oss|managed-azure|managed-aws).
#    Default: grafana-cloud.

# 2. (grafana-cloud mode only) create the OTLP credentials secret:
cp observability/otel-collector/secret.example.yaml observability/otel-collector/secret.yaml
#    edit secret.yaml with your Grafana Cloud OTLP endpoint + base64(instanceID:apiKey),
#    then:
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f observability/otel-collector/secret.yaml

# 3. (optional) export registry/git credentials consumed by scripts/01-namespaces.sh -
#    REGISTRY_USERNAME/REGISTRY_PASSWORD become both the Jenkins "container-registry"
#    push credential and the "ghcr-credentials" imagePullSecret in every Microservices
#    namespace (needed if MICROSERVICES_REGISTRY packages are private, the GHCR default)
export REGISTRY_USERNAME=<github-username> REGISTRY_PASSWORD=<ghcr-token>
export GIT_USERNAME=<github-username>      GIT_TOKEN=<github-token>

# 4. provision everything
./scripts/up.sh

# 5. check status / get port-forward commands
./scripts/status.sh

# tear down (namespaces kept by default; see scripts/down.sh)
./scripts/down.sh
```

`scripts/up.sh` runs, in order: prereq/repo checks → namespaces, secrets & NetworkPolicies → the OpenTelemetry Operator → **ArgoCD** (`08.5`, installed *before* observability because the OSS stack is GitOps-managed by ArgoCD) → the observability backend (`03`) → the selected CI engine and its pipelines (`04`/`06` — Jenkins+seed, or Tekton+pipelines per `ci.engine`) → Grafana dashboards (`07`) → Grafana alerts (`07.5`) → Headlamp (`08`) → Gateway + routes/IAP (`09`) → wait for the microservices Deployments, then the OTel injection self-heal guard. Every step is idempotent (`helm upgrade --install` / `kubectl apply`), so re-running `up.sh` after a partial failure is safe. Each step also runs standalone: `./scripts/0N-*.sh`.

## Step-by-Step Deployment Guide (For Other People)

This guide walks through deploying the entire POC (Infrastructure, Jenkins pipelines-as-code, ArgoCD GitOps, and Observability stack) from scratch on your own GKE cluster.

### Step 1: Fork and Clone the Repositories

Since this is a two-repo GitOps setup, you must fork both repositories:
1. Fork and clone **[`jenkins-2026`](https://github.com/nubenetes/jenkins-2026)** (this infrastructure repository).
2. Fork and clone **[`jenkins-2026-gitops-config`](https://github.com/nubenetes/jenkins-2026-gitops-config)** (the GitOps config repository).

### Step 2: Configure Repository Targets

Update the repository reference URLs in `config/config.yaml` to point to your forks:
- Edit `jenkins.selfRepoUrl` to point to your fork (e.g., `https://github.com/YOUR_ORG/jenkins-2026.git`).
- Edit `microservices.git.org` to match your GitHub organization or username.
- Commit and push this change to your infra repo fork.

### Step 3: Configure GKE / OAuth Credentials (Optional)

If you want to enable public access (Identity-Aware Proxy load balancer) or "Sign in with Google" OIDC login:
1. **Google OAuth Client for Jenkins**: Follow [401. Jenkins](./401-JENKINS.md) to create an OAuth client. Register `<your-jenkins-url>/securityRealm/finishLogin` as the redirect URI.
2. **Google Identity-Aware Proxy (IAP) (GKE only)**: Follow [501. Platform Operations](./501-PLATFORM_OPERATIONS.md) to set up the OAuth client gating the endpoints.

### Step 4: Add GitHub Repository Secrets

In your fork of the infra repository, go to **Settings > Secrets and variables > Actions** and add:
- `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`: Credentials for your container registry.
- `GIT_USERNAME` / `GIT_TOKEN`: GitHub account credentials used by the Jenkins pipeline.
- `JENKINS_OIDC_CLIENT_ID` / `JENKINS_OIDC_CLIENT_SECRET`: Google OAuth client credentials for Jenkins Google login.
- `JENKINS_OIDC_ADMIN_EMAIL`: Your Google email address — granted Admin roles in both Jenkins and ArgoCD.
- `HEADLAMP_ADMIN_EMAILS`: Comma-separated list of Google emails granted GCP IAP access.

See [102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md) for the complete secrets reference.

### Step 5: (Optional) Set Up Grafana Cloud Stack

If using the default `observability.mode: grafana-cloud`:
1. Log into your [Grafana Cloud Portal](https://grafana.com/) and copy your OTLP endpoint and Access Policy token.
2. Manually install the **`grafana-jenkins-datasource`** plugin inside your Grafana Cloud stack.
3. Locally create `observability/otel-collector/secret.yaml`:
   ```bash
   kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f observability/otel-collector/secret.yaml
   ```

### Step 6: Deploy the Stack

```bash
# Ensure you have set your kubectl context to your target cluster
./scripts/up.sh
```

### Step 7: Run Pipelines & Verify

Once deployed:
1. Run `./scripts/status.sh` to obtain the port-forwarding commands and passwords.

**With `ci.engine=jenkins` (default):**
2. Port-forward to Jenkins: `kubectl -n jenkins port-forward svc/jenkins 8080:8080` and open `http://localhost:8080`.
3. Log in with the administrative basic password or click **Sign in with Google**.
4. In the Jenkins dashboard, run the seeded pipelines (`gateway` and `jhipstersamplemicroservice`) to build and push their first Docker images.
5. Trigger the `microservices-k6-smoke` pipeline in Jenkins to generate synthetic traffic and verify telemetry in Grafana.

**With `ci.engine=tekton`:** the normal trigger is a `git push` to a microservices fork (Pipelines-as-Code). To run one by hand, use the ready-made manifests — no hand-config needed:
```bash
kubectl create -f tekton/runs/gateway.yaml                    # build the gateway
kubectl create -f tekton/runs/jhipstersamplemicroservice.yaml # build the other service
kubectl create -f tekton/runs/k6-smoke.yaml                   # synthetic traffic
```
Or paste one into the Tekton Dashboard's *Create PipelineRun* (YAML mode) once, then click **Rerun** for true one-click reruns. See [403 § Running a pipeline by hand](./403-TEKTON.md#running-a-pipeline-by-hand-dashboard--kubectl--tkn).

## Automated End-to-End Test (Provisioning + Decommissioning)

[`test/e2e.sh`](../test/e2e.sh) fully automates a real run of this PoC, **including the GKE cluster itself** — the one exception to "this repo assumes an existing cluster":

1. **`terraform -chdir=terraform/gke apply`** — provisions a throwaway GKE cluster.
2. **`gcloud container clusters get-credentials`** — points `kubectl`/`helm` at the new cluster.
3. **`scripts/00-check-prereqs.sh` + `scripts/01-namespaces.sh`**.
4. **`scripts/up.sh`** — the full stack, exactly as in Quick start.
5. **`test/smoke-test.sh`** — verifies Jenkins controller pod is `Running`, seed job created the stable pipelines, OTel Operator/collectors are running, and both Microservices namespaces have all `Deployment`s.
6. **`scripts/down.sh`** (with `J2026_DELETE_NAMESPACES=true`) then **`terraform -chdir=terraform/gke destroy`** — decommissions everything.

Step 6 runs **unconditionally** via an `EXIT` trap, even if steps 1-5 fail partway through, so a failed run still leaves the GCP project clean.

### Running It

```bash
cp test/.env.example test/.env   # edit: at minimum set GCP_PROJECT_ID
set -a; source test/.env; set +a

gcloud auth login
gcloud auth application-default login

./test/e2e.sh
```

### Prerequisites for e2e

- A GCP project with billing enabled, and the authenticated principal having `roles/container.admin`, `roles/compute.networkAdmin`, `roles/iam.serviceAccountAdmin` and `roles/resourcemanager.projectIamAdmin` (or `roles/owner`/`roles/editor`).
- [`terraform`](https://developer.hashicorp.com/terraform/install) >= 1.9 and the [`gcloud` CLI](https://cloud.google.com/sdk/docs/install), in addition to the prerequisites above.
- `observability.mode: grafana-cloud` (the default) requires `observability/otel-collector/secret.yaml` to already exist. For a fully self-contained run with **no** external account, `export JENKINS2026_OBS_MODE=oss` instead.

### Resource Quotas & QoS (Cost Control)

All namespace `ResourceQuota` objects are strictly configured to prevent GKE auto-scaling:

| Namespace | Workload | CPU Requests | CPU Limits | Memory Requests | Memory Limits |
|---|---|---|---|---|---|
| **jenkins** | `jenkins` | `500m` | `1.5` | `1.5Gi` | `3Gi` |
| **microservices** | `gateway` | `100m` | `1.0` | `512Mi` | `1Gi` |
| | `jhipstersamplemicroservice` | `100m` | `1.0` | `512Mi` | `1Gi` |
| | Postgres clusters (CNPG) | `50m` | `200m` | `128Mi` | `256Mi` |
| **observability** | `otel-collector-gateway` | `100m` | `500m` | `256Mi` | `512Mi` |
| **headlamp** | `headlamp` | `50m` | `200m` | `64Mi` | `128Mi` |
| **pgadmin** | `pgadmin-pgadmin4` | `100m` | `500m` | `256Mi` | `512Mi` |

Namespace-level `ResourceQuota` hard limits:
- `jenkins`: Requests max `3.0` CPU / `8.0Gi` memory.
- `microservices`: Requests max `1.5` CPU / `3.0Gi` memory.
- `observability`: Requests max `3.0` CPU / `6.0Gi` memory.
- `argocd`: Requests max `1.5` CPU / `3.0Gi` memory.

### Terraform Version & Stacks

`terraform/gke/` targets Terraform **1.15.x** (`required_version >= 1.9`) and `hashicorp/google ~> 6.0`. [Terraform Stacks](https://developer.hashicorp.com/terraform/cloud-docs/stacks) is an **HCP Terraform**-only feature — adopting it here would add an HCP Terraform account dependency for what is a single throwaway cluster with local state, so this repo uses a plain root module + local backend instead.

---

[← Previous: 601. DevSecOps](./601-DEVSECOPS.md) | [🏠 Home](../README.md) | [→ Next: 902. Troubleshooting](./902-TROUBLESHOOTING.md)

---

*901. Local Development — jenkins-2026*
