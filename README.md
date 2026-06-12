# jenkins-2026

A self-contained proof of concept that deploys **Jenkins** (via
[jenkinsci/helm-charts](https://github.com/jenkinsci/helm-charts)) on
**Kubernetes**, configures it entirely through Configuration-as-Code +
Job DSL ("pipelines as code"), and uses it to build, containerize and deploy
the [Spring PetClinic microservices](https://github.com/spring-petclinic/spring-petclinic-microservices)
reference application (+ its [Angular UI](https://github.com/spring-petclinic/spring-petclinic-angular))
in a **GitFlow** model - one "stable" pipeline per service tracking `master`,
and one `<service>-develop` pipeline tracking `develop`. Jenkins and every
PetClinic service are instrumented with **OpenTelemetry**, with traces,
metrics and logs correlated end-to-end in **Grafana** (Grafana Cloud by
default, or an in-cluster OSS stack).

It is compliant with **OpenShift 4.20+** and the latest **Kubernetes on
GKE/EKS/AKS** - the target platform is a config-file + environment-variable
feature flag, only one platform is active per run.

See [`docs/architecture.md`](docs/architecture.md) for the full component
diagram and repository layout, [`docs/pipelines-as-code.md`](docs/pipelines-as-code.md)
for how the 18 Jenkins pipelines are generated, [`docs/observability.md`](docs/observability.md)
for the OpenTelemetry/Grafana wiring, and [`docs/platforms.md`](docs/platforms.md)
for per-cloud notes.

## Prerequisites

- An existing Kubernetes cluster (GKE/EKS/AKS, latest stable, or OpenShift
  4.20+) and a `kubectl` context pointing at it. **This repo provisions no
  cluster infrastructure.**
- `kubectl`, `helm` (v3), [`yq`](https://github.com/mikefarah/yq) (Go
  version, `mikefarah/yq`), `git`, `bash`. `gh` (GitHub CLI) only if you plan
  to push this repo yourself.
- Cluster permissions to create namespaces, RBAC, CRDs (OpenTelemetry
  Operator) and the workloads described below.
- A container registry you can push to (default:
  `ghcr.io/nubenetes/jenkins-2026-petclinic` - works anonymously for pulls;
  pushing needs a token with `write:packages` in the `jenkins-credentials`
  Secret, see below).
- (default observability mode) A [Grafana Cloud](https://grafana.com/products/cloud/)
  stack (free tier is enough) for its OTLP gateway endpoint + API key.

## Quick start

```bash
# 1. Review/edit config/config.yaml - platform.target (gke|eks|aks|openshift)
#    and observability.mode (grafana-cloud|oss|managed). Defaults: gke + grafana-cloud.

# 2. (grafana-cloud mode only) create the OTLP credentials secret:
cp observability/otel-collector/secret.example.yaml observability/otel-collector/secret.yaml
#    edit secret.yaml with your Grafana Cloud OTLP endpoint + base64(instanceID:apiKey),
#    then:
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f observability/otel-collector/secret.yaml

# 3. (optional) export registry/git credentials consumed by scripts/01-namespaces.sh
export REGISTRY_USERNAME=<github-username> REGISTRY_PASSWORD=<ghcr-token>
export GIT_USERNAME=<github-username>      GIT_TOKEN=<github-token>

# 4. provision everything
./scripts/up.sh

# 5. check status / get port-forward commands
./scripts/status.sh

# tear down (namespaces kept by default; see scripts/down.sh)
./scripts/down.sh
```

`scripts/up.sh` runs, in order: prereq/repo checks -> namespaces & secrets ->
the OpenTelemetry Operator -> (in parallel) the observability stack, Jenkins,
and the initial PetClinic Helm releases -> triggers the Jenkins seed job ->
imports Grafana dashboards. Every step is idempotent
(`helm upgrade --install` / `kubectl apply`), so re-running `up.sh` after a
partial failure is safe. Each step also runs standalone:
`./scripts/0N-*.sh`.

> **First run note**: `helm/petclinic`'s default image tags (`master`/
> `develop`) won't exist in your registry yet, so PetClinic pods will show
> `ImagePullBackOff` until each service's Jenkins pipeline has run at least
> once and pushed an image. `scripts/06-seed-pipelines.sh` (part of `up.sh`)
> triggers the seed job immediately so the 18 pipelines exist right away;
> trigger individual builds from the Jenkins UI (`listView` **petclinic**) or
> wait for their 5-minute SCM-poll trigger.

## Configuration ([`config/config.yaml`](config/config.yaml))

Single source of truth, loaded by every script via
[`scripts/lib/config.sh`](scripts/lib/config.sh) (`yq` -> `J2026_*` env
vars). Two **feature flags**:

| Key | Default | Override | Meaning |
|---|---|---|---|
| `platform.target` | `gke` | `JENKINS2026_PLATFORM` env var | `gke`\|`eks`\|`aks`\|`openshift` - selects the Helm overlay, ingress/Route strategy and storage class (see [`docs/platforms.md`](docs/platforms.md)). |
| `observability.mode` | `grafana-cloud` | edit `config.yaml` | `grafana-cloud`\|`oss`\|`managed` - where traces/metrics/logs go (see [`docs/observability.md`](docs/observability.md)). |

Other notable sections: `jenkins.*` (chart coordinates, namespace, this
repo's own URL/branch used by JCasC's global library + seed job),
`observability.*` (operator/collector chart coordinates, release names,
Secret name), `petclinic.*` (namespaces for the stable/develop environments,
upstream PetClinic git org/repos/branches, target registry, and the list of
9 services seeded into Jenkins).

## Repository layout

```
config/config.yaml          single source of truth (feature flags above)
helm/jenkins/                jenkinsci/helm-charts values + per-platform overlays
helm/petclinic/              local chart for the 9 PetClinic workloads (2 envs)
jenkins/casc/                JCasC: security, OTel exporter, seed job
jenkins/pipelines/           Jenkinsfile.petclinic + seed job (Job DSL + services.yaml)
vars/, resources/            Jenkins global shared library (must be at repo root)
observability/               OTel Operator/Collector + Grafana/Loki/Tempo/Prometheus values + dashboards
scripts/                      00-07 numbered steps + up.sh / down.sh / status.sh
terraform/gke/                throwaway GKE cluster for test/e2e.sh (the one exception
                              to "assumes an existing cluster")
test/                         e2e.sh (provision -> up.sh -> smoke-test.sh -> down.sh -> destroy)
docs/                         architecture, pipelines-as-code, observability, platforms
```

Full details in [`docs/architecture.md`](docs/architecture.md).

## Pipelines as code

A Jenkins seed job (defined via JCasC, running Job DSL against
[`jenkins/pipelines/seed/seed-jobs.groovy`](jenkins/pipelines/seed/seed-jobs.groovy)
+ [`services.yaml`](jenkins/pipelines/seed/services.yaml)) generates **18
pipelines**: for each of the 9 PetClinic services, a `<service>` job tracking
`master` (deploys to namespace `petclinic`) and a `<service>-develop` job
tracking `develop` (deploys to `petclinic-develop`). Both run the same
[`Jenkinsfile.petclinic`](jenkins/pipelines/Jenkinsfile.petclinic):
checkout -> build & test -> build & push image -> `helm upgrade` the
[`helm/petclinic`](helm/petclinic) chart for that environment -> smoke test.
Details, including why the Jenkinsfile deliberately has no `parameters {}`
block, in [`docs/pipelines-as-code.md`](docs/pipelines-as-code.md).

## Observability

Jenkins (via the `opentelemetry` plugin), every Java microservice (via OTel
Operator auto-instrumentation) and the Angular UI (via a small RUM snippet)
export OTLP to an in-cluster collector, which forwards to Grafana Cloud
(default) or an in-cluster Prometheus+Loki+Tempo+Grafana stack
(`observability.mode: oss`). Two pre-built dashboards
(`observability/grafana/dashboards/`) cover Jenkins CI health and PetClinic
service health, with derived-field/exemplar links so you can jump from a log
line or a latency spike straight to the trace that produced it. Full details
in [`docs/observability.md`](docs/observability.md).

## Automated end-to-end test (provisioning + decommissioning)

[`test/e2e.sh`](test/e2e.sh) fully automates a real run of this PoC,
**including the GKE cluster itself** - the one exception to "this repo
assumes an existing cluster" (scoped entirely to `terraform/gke/` and
`test/`):

1. **`terraform -chdir=terraform/gke apply`** - provisions a throwaway GKE
   cluster: its own VPC/subnet and a 2-4 node autoscaling `e2-standard-4`
   node pool.
2. **`gcloud container clusters get-credentials`** - points `kubectl`/`helm`
   at the new cluster.
3. **`scripts/00-check-prereqs.sh` + `scripts/01-namespaces.sh`**.
4. **`scripts/up.sh`** - the full stack, exactly as in Quick start.
5. **`test/smoke-test.sh`** - verifies the Jenkins controller pod is `Running`
   and serves `/login`, the seed job created all 19 jobs (18 pipelines +
   `seed-jobs`), the OTel Operator/collectors (and, for `oss` mode, Grafana)
   are running, and both PetClinic namespaces have all 9 `Deployment`s.
6. **`scripts/down.sh`** (with `J2026_DELETE_NAMESPACES=true`) then
   **`terraform -chdir=terraform/gke destroy`** - decommissions everything.

Step 6 runs **unconditionally** via an `EXIT` trap, even if steps 1-5 fail
partway through, so a failed run still leaves the GCP project clean.

### Running it

```bash
cp test/.env.example test/.env   # edit: at minimum set GCP_PROJECT_ID
set -a; source test/.env; set +a

gcloud auth login
gcloud auth application-default login

./test/e2e.sh
```

### Prerequisites

- A GCP project with billing enabled, and the authenticated principal having
  `roles/container.admin`, `roles/compute.networkAdmin`,
  `roles/iam.serviceAccountAdmin` and `roles/resourcemanager.projectIamAdmin`
  (or `roles/owner`/`roles/editor`).
- [`terraform`](https://developer.hashicorp.com/terraform/install) >= 1.9
  (developed against **1.15.x**) and the
  [`gcloud` CLI](https://cloud.google.com/sdk/docs/install), in addition to
  the [Prerequisites](#prerequisites) above (`kubectl`/`helm`/`yq`/etc).
- `observability.mode: grafana-cloud` (the default) requires
  `observability/otel-collector/secret.yaml` to already exist (Quick start
  step 2) - `test/e2e.sh` checks for it up front and fails fast with
  instructions if it's missing. For a fully self-contained run with **no**
  external account, `export JENKINS2026_OBS_MODE=oss` instead (see
  `test/.env.example`).

### What gets created / destroyed

[`terraform/gke/`](terraform/gke/) provisions, all named/prefixed
`jenkins-2026*` and removed by `terraform destroy`:

| Resource | Notes |
|---|---|
| VPC + subnet (`jenkins-2026-vpc` / `-subnet`) | VPC-native, dedicated pod/Service CIDR ranges |
| GKE cluster `jenkins-2026` (zonal, `us-central1-a`) | `deletion_protection = false` so `destroy` works |
| Node pool (2-4 x `e2-standard-4`, autoscaling) | sized for Jenkins + 18 PetClinic pods + 1-2 concurrent build agents |
| Service account `jenkins-2026-nodes` + IAM bindings | logging/monitoring writer, Artifact Registry reader only |

`container.googleapis.com`/`compute.googleapis.com` API enablement on the
project is intentionally left in place (re-enabling is slow, and disabling
can break unrelated resources in the same project).

### Cost

At on-demand `us-central1` pricing, the cluster runs at roughly
**$0.40-0.50/hr** (3x `e2-standard-4`, plus the $0.10/hr GKE cluster
management fee - waived for your first zonal cluster per billing account).
A full `test/e2e.sh` pass (provision, deploy, smoke-test, tear down
everything) typically takes **15-25 minutes**, i.e. **~$0.10-0.20 per run**.
Grafana Cloud's free tier comfortably covers this PoC's traffic/series volume
for a run of that length.

### Terraform version & Stacks

`terraform/gke/` targets Terraform **1.15.x** (`required_version >= 1.9`) and
`hashicorp/google ~> 6.0`. [Terraform
Stacks](https://developer.hashicorp.com/terraform/cloud-docs/stacks) (the
newer multi-component/multi-deployment orchestration model) is an **HCP
Terraform**-only feature aimed at fleets of similar deployments across
environments - adopting it here would add an HCP Terraform account dependency
for what is a single throwaway cluster with local state, so this repo uses a
plain root module + local backend instead. The resources in
[`terraform/gke/main.tf`](terraform/gke/main.tf) can be lifted into a Stack
component largely as-is if you use HCP Terraform for your own infrastructure.

## Troubleshooting

- **`yq` not found**: install [`mikefarah/yq`](https://github.com/mikefarah/yq)
  (the Go binary - not the Python `yq` wrapper around `jq`).
- **`scripts/03-observability.sh` fails with "Secret ... not found"**: create
  `observability/otel-collector/secret.yaml` from the `.example` template
  and `kubectl apply` it (see Quick start step 2) before re-running.
- **PetClinic pods stuck in `ImagePullBackOff`**: expected before any
  pipeline has run for that service - see the "First run note" above. Check
  `kubectl -n petclinic describe pod <pod>` to confirm it's an image-pull
  issue, then trigger that service's job in Jenkins.
- **OpenShift: `docker` container fails to start (privileged)**: see the
  "Known manual step" in [`docs/platforms.md`](docs/platforms.md) -
  `oc adm policy add-scc-to-user privileged -z jenkins -n jenkins`.
- **Re-running after a partial failure**: every step is idempotent; just
  re-run `./scripts/up.sh` (or the individual `scripts/0N-*.sh`). Logs from
  the last `up.sh`/`down.sh` run are under `logs/`.
- **Rotating the Jenkins admin password**: delete the `jenkins-credentials`
  Secret in the `jenkins` namespace and re-run `scripts/01-namespaces.sh` +
  `scripts/04-jenkins.sh`.
- **`test/e2e.sh` was interrupted (Ctrl-C) or `terraform destroy` failed**:
  the `EXIT` trap should still have run `terraform destroy`, but to be sure
  no billable resources are left, run
  `terraform -chdir=terraform/gke destroy` manually and confirm with
  `gcloud container clusters list --project "$GCP_PROJECT_ID"`.

## License

[MIT](LICENSE) © 2026 Nubenetes
