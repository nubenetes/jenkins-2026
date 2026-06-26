[← Previous: 602. Version Pinning](./602-VERSION_PINNING.md) | [🏠 Home](../README.md) | [→ Next: 902. Troubleshooting](./902-TROUBLESHOOTING.md)

---

# 901. Local Development

## Prerequisites

| Tool | Why | Install |
| :--- | :--- | :--- |
| `kubectl`, `helm` (v3) | deploy workloads | cluster toolchain |
| [`yq`](https://github.com/mikefarah/yq) (Go version) | parse `config/config.yaml` | `brew install yq` / [releases](https://github.com/mikefarah/yq/releases) |
| `gcloud` + `gsutil` | GCP auth, Secret Manager, ADC | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| `terraform` (≥ 1.9) | bootstrap + GKE cluster | [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/downloads) |
| `gh` (GitHub CLI) | set repo secrets (bootstrap) | [cli.github.com](https://cli.github.com/) |
| `git`, `bash` | source control + scripts | standard |

You also need:
- A **GCP project** with **billing enabled** and **Owner** (or Editor + `resourcemanager.projectIamAdmin`) on it.
- Push / admin access to the GitHub repo (to set its secrets).
- A container registry you can push to (default: `ghcr.io/nubenetes/jenkins-2026-microservices` — anonymous pulls; pushing needs a `write:packages` token).
- **ArgoCD OIDC Redirect URI**: add `https://argocd.<baseDomain>/api/dex/callback` to your Google OAuth client's **Authorized redirect URIs**.
- (default observability mode) A [Grafana Cloud](https://grafana.com/products/cloud/) stack (free tier is enough) for its OTLP gateway endpoint + API key.

### Operator workstation setup (`scripts/dev-setup.sh`)

If you drive an **already-provisioned** cluster from your laptop (Linux/WSL), run this **after every from-scratch rebuild** to point your machine at the new cluster:

```bash
bash scripts/dev-setup.sh   # 'bash …' the first time, in case the +x bit is missing
```

It is idempotent and configures **only your machine** (no cloud resources). Six steps: checks the required CLIs → ensures `gcloud` auth (user + ADC) → resolves the project → installs `gke-gcloud-auth-plugin` → **refreshes the kubeconfig** for the current cluster → restores the scripts' `+x` bits. It auto-discovers the cluster (or take `CLUSTER_NAME` / `CLUSTER_LOCATION` / `PROJECT_ID` overrides).

It is the cure for the post-rebuild **`Unable to connect to the server: dial tcp <old-ip>:443: i/o timeout`**: a rebuild rotates the control-plane IP, so a kubeconfig from a previous incarnation goes stale (see [902 § Troubleshooting](./902-TROUBLESHOOTING.md)). It is intentionally **not** part of `bootstrap.sh` (Day0 — runs before any cluster exists) or `up.sh` (platform-agnostic — works against whatever `kubectl` context you give it).

> **Just the permissions?** If you only hit `-bash: ./scripts/up.sh: Permission denied` (an editor/OS dropped the bit — all scripts are committed `100755`), the minimal fix is:
> ```bash
> chmod +x scripts/*.sh scripts/lib/*.sh test/*.sh
> ```

## Quick Start

```bash
# 0. (once, before anything else) Bootstrap the GCP root of trust.
#    Creates the WIF trust, GCS state bucket, CI service account, permanent DNS zone,
#    and sets the 4 GitHub repo secrets. See docs/100-BOOTSTRAP.md.
./scripts/bootstrap.sh up

# 1. Review/edit config/config.yaml - observability.mode (grafana-cloud|oss|managed-azure|managed-aws),
#    ci.engine (jenkins|tekton), secrets.backend (imperative|eso).
#    Default: grafana-cloud + jenkins + imperative.

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

`scripts/up.sh` runs, in order: prereq/repo checks → namespaces, secrets & NetworkPolicies → the OpenTelemetry Operator ��� **ArgoCD** (`08.5`, installed *before* observability because the OSS stack is GitOps-managed by ArgoCD) → External Secrets sync (`08.6`, only when `secrets.backend=eso`) → the observability backend (`03`) → the selected CI engine and its pipelines (`04`/`06` �� Jenkins+seed, or Tekton+pipelines per `ci.engine`) → Grafana dashboards (`07`) → Grafana alerts (`07.5`) → Headlamp (`08`) → Gateway + routes/IAP (`09`) → wait for the microservices Deployments, then the OTel injection self-heal guard. Every step is idempotent (`helm upgrade --install` / `kubectl apply`), so re-running `up.sh` after a partial failure is safe. Each step also runs standalone: `./scripts/0N-*.sh`.

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

### Step 3: Bootstrap — Root of Trust + Public DNS Zone

> **Run once, by hand, on your laptop.** This is the only step that cannot be a GitHub Actions workflow (it creates the WIF trust and GCS bucket that all other workflows depend on). See [100. Bootstrap](./100-BOOTSTRAP.md) for the full explanation.

```bash
# (optional) pass inputs non-interactively:
# export PROJECT_ID=my-gcp-project REGION=us-central1 GITHUB_REPO=myorg/jenkins-2026
./scripts/bootstrap.sh up
```

What it creates:
- **WIF trust** + CI service account — lets GitHub Actions authenticate to GCP keylessly.
- **GCS state bucket** — remote Terraform state for every other module.
- **Permanent public DNS zone** `jenkins-2026-public-zone` for `base_domain` (e.g. `jenkins2026.nubenetes.com`) — lives in the never-destroyed root tier so its nameservers never change across cluster rebuilds.
- **4 GitHub repo secrets** (`GCP_PROJECT_ID`, `TF_STATE_BUCKET`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`).

It is **idempotent**: re-run any time to converge (e.g. after adding a role or renewing a permission).

#### One-time DNS delegation (Squarespace / your parent DNS)

After `bootstrap.sh up`, delegate the subdomain to Cloud DNS **once for the life of the project**:

1. Get the zone's nameservers:
   ```bash
   terraform -chdir=terraform/bootstrap output dns_zone_name_servers
   ```
   Example output: `["ns-cloud-a1.googledomains.com.", "ns-cloud-a2.googledomains.com.", ...]`

2. In your parent domain's DNS (e.g. Squarespace for `nubenetes.com`):
   - **Add 4 `NS` records** for the subdomain host (e.g. `jenkins2026`) pointing to those 4 nameservers.
   - **Delete** any pre-existing `A` or `CNAME` records for `*.jenkins2026` (they conflict with the delegation).

3. Run `Day0.infra.01` (or `Day1.cluster.00`) — it populates the zone with the wildcard-A record (`*.jenkins2026 → <external IP>`) and the cert-validation CNAME. From this point on, every Decom+rebuild reuses the same zone and the same NS delegation ��� **no further DNS changes required**.

> **Why this is permanent:** the zone lives in the root tier (`terraform/bootstrap`), which is only destroyed when you intentionally abandon the project (`bootstrap.sh down`). Even a full `Decom.infra.00` teardown leaves the zone and its nameservers in place. Only the A and CNAME records (managed by `gateway-bootstrap`) are recreated on each rebuild.

### Step 4: Configure GKE / OAuth Credentials (Optional)

If you want to enable public access (Identity-Aware Proxy load balancer) or "Sign in with Google" OIDC login:
1. **Google OAuth Client for Jenkins**: Follow [401. Jenkins](./401-JENKINS.md) to create an OAuth client. Register `<your-jenkins-url>/securityRealm/finishLogin` as the redirect URI.
2. **Google Identity-Aware Proxy (IAP) (GKE only)**: Follow [501. Platform Operations](./501-PLATFORM_OPERATIONS.md) to set up the OAuth client gating the endpoints.

### Step 5: Add Remaining GitHub Repository Secrets

The bootstrap already set the 4 GCP secrets. Add the remaining application-layer secrets in **Settings > Secrets and variables > Actions**:
- `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`: Credentials for your container registry.
- `GIT_USERNAME` / `GIT_TOKEN`: GitHub account credentials used by the Jenkins pipeline.
- `JENKINS_OIDC_CLIENT_ID` / `JENKINS_OIDC_CLIENT_SECRET`: Google OAuth client credentials for Jenkins Google login.
- `JENKINS_OIDC_ADMIN_EMAIL`: Your Google email address — granted Admin roles in both Jenkins and ArgoCD.
- `HEADLAMP_ADMIN_EMAILS`: Comma-separated list of Google emails granted GCP IAP access.

See [102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md) for the complete secrets reference.

### Step 6: (Optional) Set Up Grafana Cloud Stack

If using the default `observability.mode: grafana-cloud`:
1. Log into your [Grafana Cloud Portal](https://grafana.com/) and copy your OTLP endpoint and Access Policy token.
2. Manually install the **`grafana-jenkins-datasource`** plugin inside your Grafana Cloud stack.
3. Locally create `observability/otel-collector/secret.yaml`:
   ```bash
   kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f observability/otel-collector/secret.yaml
   ```

### Step 7: Deploy the Stack

```bash
# Ensure you have set your kubectl context to your target cluster
./scripts/up.sh
```

### Step 8: Run Pipelines & Verify

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
4. **`scripts/up.sh`** �� the full stack, exactly as in Quick start.
5. **`test/smoke-test.sh`** — CI-engine-aware: verifies the active CI engine is up (Jenkins controller `Running` + seed pipelines, or the Tekton stack + PaC Repository CRs/PipelineRuns), OTel Operator/collectors are running, and the **stable** Microservices namespace has all `Deployment`s (the `develop` tier is off by default).
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

[← Previous: 602. Version Pinning](./602-VERSION_PINNING.md) | [🏠 Home](../README.md) | [→ Next: 902. Troubleshooting](./902-TROUBLESHOOTING.md)

---

*901. Local Development — jenkins-2026*
