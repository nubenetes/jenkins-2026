# Pipelines as Code

Everything Jenkins-side is defined in this repository - security, the global
shared library, the OpenTelemetry exporter, and the PetClinic pipelines (9
stable jobs at the root + 9 `pac-dev/*-develop` dev-sandbox jobs) - and
applied via **Configuration as Code (JCasC)** + the **Job DSL** plugin.
Nothing is configured by hand in the Jenkins UI.

## JCasC fragments ([`jenkins/casc/`](../jenkins/casc/))

`scripts/04-jenkins.sh` installs the jenkinsci/helm-charts `jenkins` chart
with three JCasC fragments passed via `--set-file`:

| File | Purpose |
|---|---|
| [`jcasc-base.yaml`](../jenkins/casc/jcasc-base.yaml) | Security realm (OIDC with Google, escape-hatch `admin` password from the `jenkins-credentials` Secret), Role-Based Authorization Strategy (`admin` global role; `developer` and `platform-engineer` item roles - see [below](#pipelines-as-code-dev-sandbox-pac-dev)), system message, **global pipeline library** `petclinic-shared-library`, and credentials (`container-registry`, `petclinic-git`). |
| [`jcasc-otel.yaml`](../jenkins/casc/jcasc-otel.yaml) | Configures the `opentelemetry` plugin's global exporter - OTLP/gRPC to `otel-collector-gateway.observability.svc.cluster.local:4317`. |
| [`jcasc-seed-job.yaml`](../jenkins/casc/jcasc-seed-job.yaml) | Defines two pipeline jobs: `seed-jobs` (tracks `main`) and `pac-dev/seed-jobs-dev` (tracks `develop`). |

## Global shared library ([`vars/`](../vars/), [`resources/`](../resources/))

Four steps used by every pipeline: `petclinicBuild`, `petclinicImage`, `petclinicDeploy`, and `petclinicSmokeTest`. They handle everything from Maven/NPM builds to Helm deployments and OTel-instrumented smoke tests.

## The seed job ([`jenkins/pipelines/seed/`](../jenkins/pipelines/seed/))

`seed_jobs.groovy` reads [`services.yaml`](../jenkins/pipelines/seed/services.yaml) to generate two distinct tracks of pipelines:

### Pipeline Model Matrix

| Feature | Stable Track (Root) | Sandbox Track (`pac-dev/`) |
| :--- | :--- | :--- |
| **Jenkins View** | `petclinic` (root-level) | `petclinic-develop` (root-level) |
| **Jenkins Folder** | Root `/` | `pac-dev/` |
| **This Repo Branch** | `main` | `develop` |
| **PetClinic Branch** | `main` | `main` |
| **Target Namespace** | `petclinic` | `petclinic-develop` |
| **RBAC Access** | `developer` (Read/Build) | `platform-engineer` (Admin) |
| **Tracking Job** | `seed-jobs` | `pac-dev/seed-jobs-dev` |

### Why no `parameters { }` block in the Jenkinsfile?

`<service>` and `pac-dev/<service>-develop` run the exact same
[`Jenkinsfile.petclinic`](../jenkins/pipelines/Jenkinsfile.petclinic). What
differs is **only** the job's parameter *defaults*, set by Job DSL:
`GIT_BRANCH`, `TARGET_NAMESPACE`, `ENV_NAME` etc.

Declarative Pipeline's `parameters { }` block overwrites a job's parameter
*definitions* on every run. Since both jobs share one Jenkinsfile from SCM, a
`parameters { }` block there would make both jobs converge on the same
defaults - destroying the stable/dev-sandbox distinction. Parameter
definitions are therefore kept entirely in `seed_jobs.groovy`.

## Pipeline stages ([`Jenkinsfile.petclinic`](../jenkins/pipelines/Jenkinsfile.petclinic))

1. **Checkout jenkins-2026** (Helm chart + shared lib resources).
2. **Checkout PetClinic source** (into `./petclinic-src`).
3. **Build & Test** (`petclinicBuild`).
4. **Build & Push Image** (`petclinicImage`).
5. **Deploy to Kubernetes** (`petclinicDeploy`).
6. **Smoke Test** (`petclinicSmokeTest`).

## Pipelines-as-code dev sandbox (`pac-dev/`)

The `pac-dev/` folder provides an isolated environment where devops/platform
engineers can iterate on the pipelines themselves.

### How it's generated

`pac-dev/seed-jobs-dev` runs the same Job DSL script as `seed-jobs`, but
checked out from the `develop` branch. It creates the
`pac-dev/<service>-develop` jobs which use the Jenkinsfile and shared
library from the `develop` branch.

### Isolation and Visibility

The sandbox is fully isolated from the stable pipelines:
- **Namespace**: Deploys to `petclinic-develop`.
- **RBAC**: The `developer` role pattern explicitly excludes the `pac-dev/`
  folder and the root-level `petclinic-develop` view.
- **Views**: The **`petclinic`** view shows stable jobs at the root. The
  **`petclinic-develop`** view (also at the root) shows sandbox jobs but is
  restricted to platform engineers and admins.

### Iteration workflow

1. Push changes to `develop`.
2. Re-run `pac-dev/seed-jobs-dev`.
3. Run `pac-dev/<service>-develop` to validate.
4. PR from `develop` to `main` to promote changes to stable.
