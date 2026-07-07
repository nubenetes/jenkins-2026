[← Previous: 101. GitHub Actions Workflows](./101-GITHUB_ACTIONS_WORKFLOWS.md) | [🏠 Home](../README.md) | [→ Next: 103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md)

---

# 102. GitHub Actions Automation

[`Day1.cluster.01-gke.yml`](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.01-gke.yml) and
[`Decom.cluster.01-gke.yml`](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.cluster.01-gke.yml)
are the CI equivalent of [`test/e2e.sh`](../test/e2e.sh), split into two manually-triggered
workflows so the cluster can be left running between them (e.g. provision in
the morning, demo it, decommission in the evening). They run the exact same
[`terraform/gke`](../terraform/gke) + `scripts/0N-*.sh` + [`test/smoke-test.sh`](../test/smoke-test.sh) as [`test/e2e.sh`](../test/e2e.sh),
but since each is a separate workflow run on a fresh runner, Terraform state
has to be **remote** (a GCS bucket) instead of local so the decommission run
can find what the provision run created.

## Bootstrapping Architecture: Persistent vs. Short-Lived Resources

To keep operating costs low and deployment speed high, this project separates the environment lifecycle into **short-lived workload resources** (GKE cluster, database pods, Helm releases) and **persistent, account-level resources (bootstrap)**. We use specialized bootstrap stages for the following reasons:

<details>
<summary>🧠 Mental model — CI automation (mindmap)</summary>

```mermaid
mindmap
  root((CI Automation))
    Identity keyless
      WIF trust
      CI service account
      GitHub OIDC token
      no JSON key
    Terraform state
      GCS bucket
      remote and shared across runs
    Resource tiers
      Persistent Day0 bootstrap
      Short-lived Day1 cluster
    Lifecycle
      Day0 infra
      Day1 cluster
      Day2 ops
      Decom teardown
    Approval gates
      two active gates
      gke-production required reviewer
      aws-bootstrap typed confirm no reviewer
```

</details>

**Reading it —** the five branches are the pillars of how this project drives GCP from CI: a **keyless identity** (WIF — no stored JSON key), **remote Terraform state** (a GCS bucket shared across separate workflow runs), the **persistent-vs-short-lived** resource split (so a teardown keeps your IP/cert/dashboards), the **DayN lifecycle** phases, and the **five approval gates**. Everything below is just detail on one of these.

<details>
<summary>🟢 For newcomers — the mental model</summary>

Everything here runs in **GitHub Actions**, but the resources split into two tiers by lifetime:

| Tier | Examples | Lifetime |
|---|---|---|
| **Persistent (Day0 bootstrap)** | WIF trust + CI service account, the GCS state bucket, the permanent DNS zone, the Grafana Cloud / Azure / AWS observability backends | created once, **kept** across cluster rebuilds |
| **Short-lived (Day1 cluster)** | the GKE cluster, database pods, Helm releases, in-cluster workloads | created and destroyed on demand |

The point of the split: tearing the cluster down (to stop billing) must **not** lose your IP, certificate, dashboards, or metrics history — those live in the persistent tier. The other surprise for newcomers: GitHub Actions never stores a GCP password or JSON key. It logs in **keylessly** via **Workload Identity Federation** — GitHub proves its identity with a short-lived OIDC token that Google trusts, and gets a temporary token to act as the CI service account.

</details>

<details>
<summary>🔴 For specialists — the wiring</summary>

- **Keyless auth (WIF).** A workflow requests a GitHub-signed OIDC JWT (`sub = repo:<owner>/<repo>:environment:<env>`), presents it to Google STS at the Workload Identity **provider**, and — if the provider's **attribute condition** matches this repo — receives a short-lived federated token to impersonate the CI service account (`jenkins-2026-ci@…`). No secret is stored; the trust is scoped to the repo (and optionally branch/environment) by that condition. The only repo secrets are four **non-secret identifiers** (`GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `TF_STATE_BUCKET`).
- **Remote state is mandatory, not a nicety.** `Day1.cluster.01` and `Decom.cluster.01` are **separate workflow runs on fresh runners**, so Terraform state must live in the **GCS bucket** (each module under its own prefix) — that is how a teardown run finds what a provision run created. Local state would be lost between runs.
- **Two gate mechanisms.** `gke-production` (required-reviewer) gates the cluster lifecycle, the `Day2.*` redeploy/publish/scale tiers (traffic/registry are ungated), **and** the Day0/Decom Gateway + Grafana-Cloud + Azure backends. The **AWS** bootstrap/decommission pair (`Day0.infra.04`/`Decom.infra.04`) instead runs on a dedicated **`aws-bootstrap`** environment — no reviewer, purely to isolate the OIDC trust of its `AdministratorAccess` role (see [Environment Protection](#environment-protection-and-manual-approvals)). Every destructive/persistent workflow additionally declares a typed `confirm` input (`"apply"`/`"destroy"`) on the reusable workflow itself, so each entry point (standalone dispatch, the `Day1` preflight via `workflow_call`, the `Decom.infra.00-all` umbrella) inherits it.

</details>

1. **GCP Auth and Terraform State ([`terraform/bootstrap`](../terraform/bootstrap))**:
   - **Workload Identity Federation (WIF)**: Establishes a secure, keyless trust relationship between GitHub Actions and your GCP project. GitHub can authenticate dynamically using OpenID Connect (OIDC) tokens instead of saving permanent GCP service account JSON keys inside repository secrets.
   - **GCS Remote Backend**: Sets up the persistent bucket where all GHA workflow runs store and retrieve Terraform state.

2. **Persistent External DNS & Networking (`Day0.infra.01 Gateway bootstrap`)**:
   - Provisions GCP global networking resources: a persistent static IP (`jenkins-2026-gateway-ip`), DNS authorizations, and the wildcard SSL certificate map (`jenkins-2026-cert-map`).
   - If these networking assets were tied to the short-lived GKE cluster, deleting the cluster would release the IP address and destroy the SSL certificate. This would force you to manually update DNS records at your domain registrar (e.g. Squarespace) and wait for DNS propagation every single time you provisioned a new cluster. Keeping the gateway bootstrapped persistently ensures your external endpoints are immediately reachable upon cluster creation.

3. **Persistent Observability Backend (`Day0.infra.02 Grafana Cloud bootstrap`)**:
   - Applies the Grafana Cloud stack ([`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack), generated slug). By decoupling the metrics/tracing backend from the GKE cluster, your logs, metrics, and trace history survive multiple cluster spin-ups and tear-downs (the GKE decommission `Decom.cluster.01` leaves the stack intact; only `Decom.infra.02` destroys it).

4. **Persistent Database Backups Storage ([`terraform/bootstrap`](../terraform/bootstrap))**:
   - **Postgres Backups Bucket**: Configures the persistent GCS bucket `<project>-jenkins-2026-postgres-backups` (project-scoped — GCS bucket names share one global namespace, so the project-ID prefix keeps it collision-proof across rebuilds, like the Terraform state bucket) with automated storage lifecycles (transition to `NEARLINE` after 3 days, delete after 7 days) to preserve backup histories across throwaway GKE lifecycle runs.
   - **Access Security**: Grants the GHA CI service accounts `storage.admin` permissions to manage bucket-level IAM policy bindings, enabling dynamic node service account access configuration during GKE provision runs.

#### How WIF keyless auth works (the token exchange)

The single hardest concept here — how a GitHub workflow touches GCP with **no stored key** — is a four-hop token exchange:

<details>
<summary>📊 WIF keyless auth — GitHub OIDC → Google STS → impersonate CI SA</summary>

```mermaid
sequenceDiagram
  autonumber
  participant W as GitHub Actions job
  participant GH as GitHub OIDC provider
  participant STS as Google STS (WIF provider)
  participant SA as CI service account
  participant TF as Terraform + GCS state bucket
  W->>GH: request OIDC token (permissions id-token write)
  GH-->>W: signed JWT, sub = repo owner/repo environment gke-production or aws-bootstrap
  W->>STS: exchange JWT at the Workload Identity provider
  STS->>STS: verify issuer + attribute condition (repo matches)
  STS-->>W: short-lived federated access token
  W->>SA: impersonate jenkins-2026-ci (generateAccessToken)
  SA-->>W: short-lived SA access token
  W->>TF: terraform apply, state in the project tfstate bucket
  Note over W,SA: no JSON key ever stored — every token is minted per run and expires
```

</details>

**Reading it —** *keyless* means the repo holds only **names**, not a credential: the four bootstrap outputs are the provider path, the SA email, the project ID, and the bucket — none of them secret. Each run, GitHub mints a fresh OIDC JWT; Google's WIF provider accepts it **only if its attribute condition matches this repo** (and, where set, the job's `environment`/branch), then returns a short-lived token to impersonate the CI service account. Because the token is per-run and expires, there is nothing to leak or rotate. State lives in the bucket so a *separate* `Decom` run authenticates the very same way and finds the `Day1` run's state.

## Workflow Architecture & Lifecycle Diagram

The following diagram illustrates how the persistent infrastructure bootstrap workflows, the GKE cluster provisioning/decommissioning pipelines, the application-specific redeployments, and the traffic simulation workflow interact:

<details>
<summary>🔍 Click to expand Workflow Architecture & Lifecycle Diagram</summary>

```mermaid
graph TD
    subgraph Bootstrapping ["Day-0 · Phase 0 Create (persistent, one-time)"]
        A["terraform/bootstrap<br>Owner/Admin roles"] -->|"WIF + GCS bucket<br>+ permanent DNS zone"| B["Workload Identity<br>+ Remote State<br>+ DNS zone"]
        B --> C["Day0.infra.01 Gateway<br>bootstrap<br>🔒 gke-production"]
        B --> D["Day0.infra.02 Grafana Cloud<br>bootstrap<br>🔒 gke-production"]
        B --> C2["Day0.infra.03 Azure<br>bootstrap<br>🔒 gke-production"]
        B --> C3["Day0.infra.04 AWS<br>bootstrap<br>✍️ aws-bootstrap"]
        C -->|"static IP + cert<br>+ DNS records in the zone"| F[("Gateway<br>+ Cert Map<br>+ A/CNAME records")]
        D -->|"stack ID + token"| E[("Grafana Cloud")]
    end

    subgraph GKE_Lifecycle ["Day-1 → Day-2 → Decommission · GKE Cluster Lifecycle"]
        F & E & B --> G["Day1.cluster.01 GKE provision<br>tf/gke + scripts/up.sh<br>🔒 gke-production"]
        G --> H["GKE Cluster Active<br>active CI engine (jenkins/tekton/githubactions/argoworkflows)<br>/ ArgoCD / services"]
        H --> I["Day2.redeploy.02 Redeploy Jenkins"]
        H --> J["Day2.redeploy.04 Redeploy Headlamp"]
        B --> L2["Day2.publish.04 Publish AWS dashboards<br>(no cluster needed)"]
        B --> M2["Day2.publish.03 Publish Azure dashboards<br>(no cluster needed)"]
        I & J --> H
        H --> K["Decom.cluster.01 GKE decommission<br>down.sh + tf destroy<br>🔒 gke-production"]
        K -->|"cluster gone<br>assets kept"| B
    end

    subgraph Simulation ["Day-2 · Phase 5 Update (simulation)"]
        H & E --> O["Day2.traffic.01 Traffic Simulation<br>k6 load script"]
        O -->|"live traffic"| H
        O -->|"telemetry"| E
    end

    subgraph Persistent_Teardown ["Decommission · Phase 9 Destroy (persistent, one-time)"]
        K --> P1["Decom.infra.01 Gateway<br>decommission<br>🔒 gke-production"]
        K --> P2["Decom.infra.02 Grafana Cloud<br>decommission<br>🔒 gke-production"]
        K --> P3["Decom.infra.03 Azure<br>decommission<br>🔒 gke-production"]
        K --> P4["Decom.infra.04 AWS<br>decommission<br>✍️ aws-bootstrap"]
        P1 & P2 & P3 & P4 -->|"all resources removed"| N["Clean Slate"]
    end

    classDef persistent fill:#f9f,stroke:#333,stroke-width:2px;
    classDef cluster fill:#bbf,stroke:#333,stroke-width:2px;
    classDef update fill:#bfb,stroke:#333,stroke-width:1px;
    class E,F,P1,P2,P3,P4 persistent;
    class G,H,I,J,K,O cluster;
    class L2,M2 update;
```

</details>

> 🔒 = a required-reviewer GitHub **Environment** gate (`gke-production` — the
> cluster, all Day2 cluster-ops, and the Gateway/Grafana-Cloud/Azure Day0
> backends). ✍️ = a typed `confirm` input on the workflow itself
> (`"apply"`/`"destroy"`); the **AWS** pair additionally runs on the dedicated
> no-reviewer **`aws-bootstrap`** environment that isolates its
> `AdministratorAccess` OIDC trust. See [Environment Protection and Manual Approvals](#environment-protection-and-manual-approvals).

> The four persistent teardowns (`Decom.infra.01..04`) are independent:
> - **Targeted teardown** — after `Decom.cluster.01`, run **only** the one(s) you actually provisioned (with the `oss` default, often none).
> - **Full teardown** — the opt-in **`Decom.infra.00-all` ("Everything")** umbrella tears down the cluster **and** every persistent backend in one dispatch:
>   - reuses each per-resource Decom via `workflow_call` (no duplicated teardown logic);
>   - type `destroy` to confirm; the cluster goes first, then the backends destroy in parallel;
>   - the backend checkboxes default **on**; the Gateway IP defaults **off**.
> See [101 § Decom: independent per backend, plus an opt-in umbrella](./101-GITHUB_ACTIONS_WORKFLOWS.md#decom-independent-per-backend-plus-an-opt-in-everything-umbrella).

> **What `Day1.cluster.01` bootstraps automatically — and what it does not.**
> `Day1` runs the matching **observability backend** bootstrap as a preflight job
> (`Day0.infra.0{2,3,4}` via `workflow_call`, gated by `if: observability_mode==…`),
> so the selected backend is created for you. It does **not** bootstrap the
> **Gateway**: `Day0.infra.01` is a one-time Day0 step that creates the
> persistent resources (static IP, wildcard cert map) **and the wildcard-A +
> cert-validation records inside the permanent delegated DNS zone** (the zone
> itself lives in [`terraform/bootstrap`](../terraform/bootstrap) — see [100](./100-BOOTSTRAP.md)). So DNS is
> Terraform-managed, not hand-wired: the only manual DNS step is a one-time `NS`
> delegation of `base_domain` at your parent domain. Inside `provision`,
> [`scripts/09-gateway.sh`](../scripts/09-gateway.sh) only creates the **in-cluster** `Gateway`/`HTTPRoute`
> objects, which **reference** that static IP + cert map **by name** — it does not
> create them.
>
> **Why the asymmetry:** the Gateway IP/cert are meant to **survive cluster
> rebuilds** (so DNS never has to re-propagate). That is exactly why the
> `Decom.infra.00-all` umbrella leaves the Gateway in place by default (`gateway:false`)
> — so the normal "everything decommissioned" state still has the Gateway, and a
> later `Day1` simply re-binds the in-cluster objects to the existing IP. You only
> need to (re-)run `Day0.infra.01` **before** `Day1` if you destroyed the Gateway
> **deliberately** (standalone `Decom.infra.01`, or the umbrella with
> `gateway:true`). If `gateway.baseDomain` is empty, `09-gateway.sh` skips the
> Gateway entirely.

> **One-click from scratch.** To avoid having to remember the Gateway prerequisite,
> the **`Day1.cluster.00-all` ("Everything up")** umbrella does both steps in one
> dispatch — `Day0.infra.01` (Gateway bootstrap) **then** `Day1.cluster.01` (cluster
> + full stack + the chosen backend bootstrap). It is the symmetric counterpart of
> the `Decom.infra.00-all` ("Everything") teardown: **one click up, one click down**,
> both idempotent. See [101 § Provision umbrella](./101-GITHUB_ACTIONS_WORKFLOWS.md#provision-per-step-workflows-plus-an-opt-in-everything-up-umbrella).

### Detailed Workflow Reference and Lifecycle Management

> Each workflow is tagged with its **Day-0 / Day-1 / Day-2 / Decommission** lifecycle
> position (SRE taxonomy). See [101. Workflows → Day-0 / Day-1 / Day-2 operations](./101-GITHUB_ACTIONS_WORKFLOWS.md#day-0--day-1--day-2-operations)
> for the full definition and the per-workflow table. In short: **Day-0** = persistent
> bootstrap (`Day0.infra.0N`), **Day-1** = GKE provision (`Day1.cluster.01`), **Day-2** = operations on
> the running cluster (`Day2.*`), **Decommission** = teardown (`Decom.*`).

#### 1. Persistent Bootstrap Workflows (Day-0)
- **`Day0.infra.01 Gateway bootstrap`**: Provisions account-level GCP networking assets using [`terraform/gateway-bootstrap`](../terraform/gateway-bootstrap). This includes a reserved external IP (`jenkins-2026-gateway-ip`), DNS authorizations, and a Google-managed wildcard SSL certificate map. Keeping this IP and SSL certificate persistent avoids losing the reserved IP during a GKE rebuild, eliminating the need to update wildcard DNS records at your domain registrar and wait for DNS propagation.
- **`Day0.infra.02 Grafana Cloud bootstrap`**: Provisions a dedicated Grafana Cloud stack (hosted metrics/traces/logs backend) using [`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack), with a Terraform-generated slug. By separating the observability backend from the short-lived GKE cluster, application performance metrics and history remain readable even after GKE is decommissioned and rebuilt — the stack lives until you run `Decom.infra.02 Grafana Cloud decommission`, which tears it down (the org/free tier is untouched).

#### 2. Persistent Decommission Workflows (Decommission · Clean Slate)
When you want to tear down the entire project permanently, you must run the decommission workflows in the reverse order of setup to avoid dangling resources:
1. Run **`Decom.cluster.01 GKE decommission`** first to destroy the active GKE cluster and all internal Kubernetes workloads (releasing short-lived target bindings).
2. Run **`Decom.infra.01 Gateway decommission`** to run `terraform destroy` on the gateway resources, freeing the reserved external IP, removing the wildcard SSL certificate map, and deleting GCP DNS authorizations.
3. Run **`Decom.infra.02 Grafana Cloud decommission`** to run `terraform destroy` on the Grafana Cloud stack, which removes the Grafana instances, access policies, and dashboards.

> [!WARNING]
> Decommissioning the gateway (`Decom.infra.01`) releases the external IP address. If you recreate the gateway later, a *new* IP will be allocated, forcing you to update your DNS provider's A records and wait for DNS propagation. Only decommission the gateway if you plan to shut down the environment permanently.

## Version Pinning and the `git_ref` Parameter

To support deterministic deployments and clean, error-free environment destruction, all GKE lifecycle workflows support custom Git reference checking:

* **Workflows Supported** — every cluster-lifecycle workflow: the two umbrella/provision entries ([`Day1.cluster.00-all`](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.00-all.yml), [`Day1.cluster.01-gke`](https://github.com/nubenetes/jenkins-2026/actions/workflows/Day1.cluster.01-gke.yml)), all seven `Day2.redeploy.*` (ArgoCD, Jenkins, Tekton, Headlamp, Gateway, GitHub Actions (ARC), Argo Workflows), all five `Day2.publish.*` (OSS, Grafana Cloud, Azure, AWS, alerts) and [`Decom.cluster.01-gke`](https://github.com/nubenetes/jenkins-2026/actions/workflows/Decom.cluster.01-gke.yml). (The Day0/Decom.infra bootstraps and the traffic/scale/registry workflows take no `git_ref`.)

### The `git_ref` Parameter

Each of these workflows includes a manual trigger input `git_ref` (which defaults to `""` / empty).

* **Leave Empty (Recommended)**: The checkout action automatically defaults to the branch or tag selected in the native **"Use workflow from"** dropdown menu.
* **Provide Value**: You can type in any valid branch name, tag (e.g. `v1.1.1`), or commit SHA. If specified, this custom reference will override the dropdown selection.

### Form Fields Reference (Day1.cluster.01 GKE Provision)

When executing the **Day1.cluster.01 GKE provision** workflow manually, you are presented with a form containing the following fields:

1. **Use workflow from (Dropdown - Native)**:
   - Selects the branch or tag from which GitHub Actions loads the workflow YAML file.
   - If the `git_ref` field below is left empty, the runner will check out this exact reference.

2. **observability_mode (Dropdown - Choice)**:
   - **Type**: Choice (`oss` | `grafana-cloud` | `managed-azure` | `managed-aws`).
   - **Default**: `oss` (needs no external backend; [`config/config.yaml`](../config/config.yaml)'s durable default is still `grafana-cloud` for local `up.sh`).
   - Overrides the `observability.mode` setting in [`config/config.yaml`](../config/config.yaml) for this execution lifecycle. Exactly **one** backend is active per cluster and the choice is **deterministic/idempotent** (like `ci_engine`): a rerun with a different mode auto-retires the previously-deployed backend's in-cluster footprint and provisions the chosen one. See [301 § observability backends](301-OBSERVABILITY.md).

3. **destroy_unused_backends (Checkbox - Boolean) — DESTRUCTIVE, opt-in**:
   - **Default**: `false`.
   - When `true`, also `terraform destroy` the **persistent** backend (Grafana Cloud stack / Azure / AWS Managed Grafana) of every mode you did **not** select, so only the chosen backend exists. Reuses the `Decom.infra.0{2,3,4}` workflows via `workflow_call`; independent of the cluster provision (a destroy of a never-provisioned backend can't block it).
   - ⚠ **Irreversible**: wipes that backend's history/dashboards; re-selecting the mode later recreates it empty. Needs the non-selected backends' credentials/identifiers configured.

4. **ci_engine (Dropdown - Choice)**:
   - **Type**: Choice (`jenkins` | `tekton` | `githubactions` | `argoworkflows`).
   - **Default**: `jenkins`.
   - Selects which of the **four mutually-exclusive** CI engines the platform deploys and runs the microservices pipelines-as-code on:
     - **Jenkins** — Helm chart + JCasC + Job-DSL seed ([401](./401-JENKINS.md))
     - **Tekton** — Pipelines/Triggers/Dashboard, IAP-protected ([403](./403-TEKTON.md))
     - **GitHub Actions (ARC)** — self-hosted ephemeral Spot runners, native GitHub webhooks, **no in-cluster UI** ([404](./404-GITHUB_ACTIONS.md))
     - **Argo Workflows** — Argo Workflows + Argo Events, IAP-protected Server UI ([405](./405-ARGO_WORKFLOWS.md))
   - All four share the same ~11-stage pipeline contract, the shared `resources/patch-app-source.sh` (gateway MySQL→Postgres + NoOp-cache build-time patch) and the `jenkins/pipelines/seed/services.yaml` registry.
   - Overrides `ci.engine` in [`config/config.yaml`](../config/config.yaml). **Deterministic/idempotent** (like `observability_mode`): a rerun with a different engine auto-retires the other three engines' in-cluster footprint (their ArgoCD apps + children + namespaces) via `retire_ci_engine` and deploys the chosen one.

5. **secrets_backend (Dropdown - Choice)**:
   - **Type**: Choice (`imperative` | `eso`).
   - **Default**: `imperative` (behaviour unchanged — `kubectl create secret` from the GitHub secrets).
   - Overrides `secrets.backend`. `eso` pushes the secret values to **GCP Secret Manager** and the **External Secrets Operator** syncs them into the cluster via Workload Identity (keyless, versioned, audited). The whole `up.sh` lifecycle honours it. See [201 § Secrets backend](201-ARCHITECTURE.md#secrets-backend-imperative--eso).

6. **enable_gateway (Checkbox - Boolean)**:
   - **Default**: `true`.
   - Determines whether the public GKE Gateway L7 load balancer should be provisioned.
   - **Prerequisites**: Requires `Day0.infra.01 Gateway bootstrap` applied, wildcard DNS records, and IAP OAuth client credentials.

7. **develop_track (Checkbox - Boolean)**:
   - **Default**: `false`.
   - Deploys the optional **lean `develop` microservices tier** alongside `stable`: a `microservices-develop` namespace + ArgoCD app from `values-develop.yaml` on the GitOps repo's `develop` branch (a single non-HA CNPG instance, single pooler, no backups), plus `-develop` CI jobs/runs. Engine-neutral (any of the four CI engines — Jenkins, Tekton, GitHub Actions, Argo Workflows). Overrides `microservices.developTrackEnabled` via `JENKINS2026_DEVELOP_TRACK_ENABLED`.
   - **Prerequisite**: the `jenkins-2026-gitops-config` repo must have a `develop` branch with `helm/microservices/values-develop.yaml`. See [402 § Optional develop Tier](./402-PIPELINES_AS_CODE.md).

8. **git_ref (Text Box - String)**:
   - **Default**: `""` (empty).
   - Leave empty to use the **"Use workflow from"** dropdown selection.
   - Provide a branch name, tag, or SHA to override.

9. **log_level (Dropdown - Choice)**:
   - **Type**: Choice (`info` | `debug`).
   - **Default**: `info`.
   - Script/Terraform verbosity — `debug` adds `[DEBUG]` script lines + `TF_LOG=DEBUG` (for runner-level tracing use GitHub's `ACTIONS_STEP_DEBUG`).

10. **grafana_cloud_tier (Dropdown - Choice)**:
    - **Type**: Choice (`free` | `paid`).
    - **Default**: `free`.
    - grafana-cloud mode only — `free` enables leanMetrics + `logMinSeverity=warn` to fit the free-tier limits; `paid` ships full metrics + all logs. Traces are never sampled on either tier (100% shipped, preserving trace↔log/metric correlation).

11. **log_min_severity (Dropdown - Choice)**:
    - **Type**: Choice (`auto` | `trace` | `debug` | `info` | `warn` | `error`).
    - **Default**: `auto` (derived from `grafana_cloud_tier`).
    - Overrides the minimum log severity the collector ships to Grafana.

### The Danger of Divergent References

Mixing different tags, branches, or SHAs during the lifecycle of a single GKE cluster will cause deployment and state management failures:

1. **Terraform State Conflicts**: If you provision GKE using tag `v0.8.0` and later run the decommission workflow targeting `v0.9.0`, Terraform will compare the stored GCS backend state against updated node pool, VPC, or IAM definitions — causing plan mismatches or deletion failures.
2. **Helper Script & Template Divergence**: Platform components rely on configuration schemas in [`config/config.yaml`](../config/config.yaml). Mismatched versions can cause namespace naming conventions or credential key format differences.
3. **Application and Database Incompatibility**: Mismatched versions between the infra repo and the GitOps repo can cause pods to crash due to missing secrets or incorrect network policies.

> [!IMPORTANT]
> **Rule of lockstep alignment**:
> 1. Always ensure that the `git_ref` used for provisioning (`Day1.cluster.01`) matches the `git_ref` used for decommissioning (`Decom.cluster.01`) and redeployments (any `Day2.redeploy.*` / `Day2.publish.*`).
> 2. For stable releases, pin `git_ref` to this repo's release tag (e.g. `v1.1.1`). The GitOps repo (`jenkins-2026-gitops-config`) is deliberately versioned **independently** (its own `v0.9.x` line) and ArgoCD tracks it by **branch**, not tag — its `main` is machine-pushed image-tag bumps, so no matching tag is required (or possible to keep in lockstep) there.

## Environment Protection and Manual Approvals

To enforce cost control (FinOps), auditability, and guard against accidental destruction of active resources, critical workflows are tied to a GitHub Actions **environment**.

Nearly all workflows and resource jobs run under a single GitHub Environment, **`gke-production`**, with **one deliberate exception**: the AWS bootstrap/decommission pair (`Day0.infra.04` / `Decom.infra.04`) runs under a dedicated **`aws-bootstrap`** environment (see the ⚠️ security note below).

Consolidating onto `gke-production` eliminates sequential approval fatigue. In GitHub Actions, approvals are granted per environment per workflow run. By sharing one environment across the cluster and every backend that authenticates to GCP (repository-scoped WIF) or Azure (a cross-lifecycle service principal):
1.  **Single Approval Gate**: When launching a multi-job workflow (such as the `Day1` preflight or the `Decom.infra.00-all` "Everything" umbrella), you are prompted to approve the run **only once** at the beginning of the execution.
2.  **No Downstream Stalls**: All subsequent jobs targeting the same environment run automatically without further human intervention once the initial approval is granted.

### Safety Guards
In addition to the environment-level reviewer gate, destructive workflows (e.g. `Decom.infra.0N`) use a **typed `confirm` input** (`"destroy"`), validated by a `guard` job before any real terraform or setup commands run. This provides two-factor verification for high-risk actions.

> **⚠️ Security note — why `aws-bootstrap` is NOT consolidated.** The GitHub Environment name is embedded in the OIDC token's `sub` claim (`repo:<owner>/<repo>:environment:<name>`), and each cloud's trust policy matches on that `sub`. The `AWS_BOOTSTRAP_ROLE_ARN` role carries **`AdministratorAccess`** and is hand-created (a root of trust, **not** Terraform-managed), so its trust is scoped to a **dedicated environment used by no other job** — `aws-bootstrap` — ensuring only `Day0.infra.04`/`Decom.infra.04` can assume it. Folding it into the shared `gke-production` would let *any* of the ~25 jobs on that environment assume an admin role, and — as a live failure showed — silently breaks `AssumeRoleWithWebIdentity` until the role's hand-written trust is also repointed. `aws-bootstrap` carries **no required reviewer** (the typed `confirm` guard gates it), so keeping it separate costs zero extra approvals. Azure is *not* isolated this way because the same service principal is reused across `Day0`/`Day1`/`Day2.publish`/`Decom`, so a shared subject is unavoidable short of splitting app registrations.

<details>
<summary>📊 The environment protection scheme</summary>

```mermaid
flowchart LR
  subgraph reviewed["gke-production environment (Required Reviewers)"]
    g1[gke-production]
  end
  subgraph isolated["aws-bootstrap environment (no reviewer · OIDC isolation)"]
    g5[aws-bootstrap]
  end
  g1 --> w1["Day1.cluster.01 · Decom.cluster.01<br/>+ Day2.* redeploy / publish / scale"]
  g1 --> w2["Day0.infra.01 · Decom.infra.01<br/>Gateway"]
  g1 --> w3["Day0.infra.02 · Decom.infra.02<br/>Grafana Cloud"]
  g1 --> w4["Day0.infra.03 · Decom.infra.03<br/>Azure"]
  g5 --> w5["Day0.infra.04 · Decom.infra.04<br/>AWS (AdministratorAccess)"]
```

</details>

#### Cloud Authentication Scoping (OIDC WIF)
Each cloud's OIDC trust matches on the token `sub`, which embeds the environment name. Scope them as follows:
- **AWS IAM Role Trust Condition** (`AWS_BOOTSTRAP_ROLE_ARN`, `AdministratorAccess`): `token.actions.githubusercontent.com:sub = repo:<owner>/<repo>:environment:aws-bootstrap` — the dedicated, isolated environment. **Do not** repoint this to `gke-production`.
- **Azure Entra ID subject**: `repo:<owner>/<repo>:environment:gke-production`
- **GCP IAM Workload Identity Pool**: scoped to the `repository` claim (`assertion.repository == <owner>/<repo>`), **independent of environment** — so consolidating environments never affects GCP.

### Setting up Environment Rules

Two environments need to exist in GitHub:

**`gke-production`** — the required-reviewer approval gate:

**Option A: Manual Setup (GitHub Web UI)**
1. Navigate to **Settings** -> **Environments** on your GitHub repository.
2. Click **New environment** and name it exactly: `gke-production`.
3. Under **Environment protection rules**, check the **Required reviewers** box.
4. Add the designated reviewers who must authorize deployments.
5. Save the configuration.

**Option B: Automated Setup (GitHub CLI)**
```bash
# Get the numeric GitHub ID of the reviewer user
gh api user -q '.id'

# Create or update the environment with the reviewer
gh api --method PUT repos/nubenetes/jenkins-2026/environments/gke-production \
  --header "Accept: application/vnd.github+json" \
  --input - <<EOF
{
  "prevent_self_review": false,
  "reviewers": [
    {
      "type": "User",
      "id": <USER_ID>
    }
  ]
}
EOF
```

**`aws-bootstrap`** — the OIDC-isolation environment for the AWS admin role. It needs **no reviewer** (the typed `confirm` guard is its gate); create it empty:
```bash
gh api --method PUT repos/nubenetes/jenkins-2026/environments/aws-bootstrap \
  --header "Accept: application/vnd.github+json" \
  --input - <<< '{"reviewers": []}'
```

## One-time Setup (Bootstrapping)

> **Fastest path — one command:** `./scripts/bootstrap.sh up` does everything in
> this section for you (prompts for identity, creates the bucket + WIF + CI SA,
> migrates its own state into the bucket, and sets the 4 GitHub secrets), and
> `./scripts/bootstrap.sh down` is the symmetric root teardown. See the full,
> beginner-friendly walkthrough with diagrams in [100. Bootstrap](./100-BOOTSTRAP.md).
> The manual steps below are the equivalent if you prefer to run them by hand.

> **Why this step can't itself run in GitHub Actions**: `Day1.cluster.01-gke.yml`
> and `Decom.cluster.01-gke.yml` authenticate to GCP via Workload Identity
> Federation (WIF) — but that WIF trust relationship, the CI service account,
> and the GCS state bucket don't exist yet. Something has to create them
> first using *real* GCP credentials, which is exactly what
> [`terraform/bootstrap`](../terraform/bootstrap) does. This is a one-time, local "break glass" step;
> every run after that happens entirely in GitHub Actions.

1. **Authenticate locally** as a principal with `roles/owner` (or
   `roles/editor` + `roles/resourcemanager.projectIamAdmin`) on your GCP project:

   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Run [`terraform/bootstrap`](../terraform/bootstrap)** once. This creates the GCS state bucket and
   a Workload Identity Federation pool/provider + service account that
   GitHub Actions will use to authenticate to GCP **without a JSON key**:

   ```bash
   cd terraform/bootstrap
   cp terraform.tfvars.example terraform.tfvars
   # edit terraform.tfvars: set project_id (and github_repo if you forked this repo)

   terraform init
   terraform apply
   terraform output    # copy these 4 values into GitHub secrets below
   ```

   Keep `terraform/bootstrap/terraform.tfstate` (gitignored, local-only) —
   it's the only record of these resources.

3. **Add repository secrets**, from the `terraform output` above:

   | Secret | From output |
   |---|---|
   | `GCP_PROJECT_ID` | `project_id` |
   | `GCP_WORKLOAD_IDENTITY_PROVIDER` | `workload_identity_provider` |
   | `GCP_SERVICE_ACCOUNT` | `ci_service_account_email` |
   | `TF_STATE_BUCKET` | `state_bucket` |

   ```bash
   cd terraform/bootstrap
   gh secret set GCP_PROJECT_ID                --body "$(terraform output -raw project_id)"
   gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$(terraform output -raw workload_identity_provider)"
   gh secret set GCP_SERVICE_ACCOUNT           --body "$(terraform output -raw ci_service_account_email)"
   gh secret set TF_STATE_BUCKET               --body "$(terraform output -raw state_bucket)"
   ```

4. **Optional secrets**, only needed if you use the corresponding feature. This is
   a summary — [103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md) is the
   complete, authoritative inventory:

   | Secret | Needed for |
   |---|---|
   | `REGISTRY_USERNAME` / `REGISTRY_PASSWORD` | pushing/pulling private microservice images from a private registry |
   | `GIT_USERNAME` / `GIT_TOKEN` | cloning a private Microservices fork |
   | `GRAFANA_TRACES_DASHBOARD_UID` / `OTEL_LOGS_BACKEND_URL` | `observability_mode: grafana-cloud` extras — "View trace in Grafana" link UID and logs Explore URL |
   | `GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD` | Alert notification email for `grafana-cloud` mode — **must be a member of the Grafana Cloud org** (Grafana Cloud rejects contact points addressed to non-members; set this when it differs from `JENKINS_OIDC_ADMIN_EMAIL`) |
   | `GRAFANA_ALERT_EMAIL_OSS` | Alert notification email for `oss` mode — overrides the cluster default; omit to use `JENKINS_OIDC_ADMIN_EMAIL` |
   | `GRAFANA_ALERT_EMAIL_MANAGED_AZURE` | Alert notification email for `managed-azure` mode — overrides the cluster default; omit to use `JENKINS_OIDC_ADMIN_EMAIL` |
   | `GRAFANA_ALERT_EMAIL_MANAGED_AWS` | Alert notification email for `managed-aws` mode — overrides the cluster default; omit to use `JENKINS_OIDC_ADMIN_EMAIL` |
   | `GRAFANA_ALERT_EMAIL` | Generic alert email fallback for all modes — used only when the mode-specific secret above is not set; omit if `JENKINS_OIDC_ADMIN_EMAIL` is correct for all modes |
   | `HEADLAMP_OIDC_CLIENT_ID` / `HEADLAMP_OIDC_CLIENT_SECRET` | Google OAuth client for Headlamp login |
   | `HEADLAMP_ADMIN_EMAILS` | comma-separated Google account emails granted cluster-admin via Headlamp **and** IAP access — **your own email, never committed to the repo** |
   | `JENKINS_OIDC_CLIENT_ID` / `JENKINS_OIDC_CLIENT_SECRET` | Google OAuth client for Jenkins "Sign in with Google" |
   | `JENKINS_OIDC_ADMIN_EMAIL` | Google account email granted the Jenkins `admin` role via OIDC — **your own email, never committed to the repo** |
   | `IAP_OAUTH_CLIENT_ID` / `IAP_OAUTH_CLIENT_SECRET` | OAuth client gating Jenkins/Headlamp via Identity-Aware Proxy |
   | `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` / `AZURE_GRAFANA_ADMIN_OBJECT_IDS` | `observability_mode: managed-azure` — identifiers only, no secret values |
   | `AWS_BOOTSTRAP_ROLE_ARN` / `AWS_REGION` (repo **Variable**) / `GKE_OIDC_ISSUER_URL` | `observability_mode: managed-aws` — identifiers only, no secret values. `AWS_REGION` is a GitHub Actions **Variable** (not a Secret) so its value isn't masked inside the Amazon Managed Grafana URL; workflows read `vars.AWS_REGION` with a `secrets.AWS_REGION` fallback. |
   | `AWS_DASHBOARD_PUBLISH_ROLE_ARN` | `observability_mode: managed-aws` — least-privilege IAM role for dashboard publishing |
   | `TEKTON_GITHUB_WEBHOOK_SECRET` / `PAC_WEBHOOK_SECRET` | `ci_engine: tekton` — GitHub HMAC tokens for the Tekton Triggers EventListener and the Pipelines-as-Code controller |
   | `ARC_GITHUB_APP_ID` / `ARC_GITHUB_APP_INSTALLATION_ID` / `ARC_GITHUB_APP_PRIVATE_KEY` | `ci_engine: githubactions` — GitHub App credentials for ARC runner registration (omit to fall back to the `GIT_TOKEN` PAT) |
   | `ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET` | `ci_engine: argoworkflows` — GitHub HMAC for the Argo Events EventSource (falls back to `PAC_WEBHOOK_SECRET`, else auto-generated) |
   | `K6_CLOUD_TOKEN` / `K6_CLOUD_PROJECT_ID` | optional Grafana Cloud k6 streaming for the k6 smoke pipeline (`--out cloud`) |

5. **(Optional) Full Grafana Cloud lifecycle automation** — for `observability_mode: grafana-cloud`:

   a. **Create a Grafana Cloud Access Policy token** (Grafana Cloud Portal -> **Administration** ->
      create an access policy with scopes: `stacks:read/write/delete`, `accesspolicies:read/write/delete`,
      `stack-service-accounts:write`, `datasources:read/write`, `pdc:read/write`, `stack-plugins:read/write`).
      Create a **Token** for this policy and save it.

   b. **Add the repository secret** (the stack slug is generated by Terraform, so
      it is no longer set here):
      ```bash
      gh secret set GRAFANA_CLOUD_API_TOKEN --body "<token from step a>"
      ```

   c. **Run the "Day0.infra.02 Grafana Cloud" workflow** (Actions tab →
      **Day0.infra.02 Grafana Cloud** → **Run workflow**).

6. **(Optional) Azure backend** for `observability_mode: managed-azure`:

   a. **Create the GitHub-OIDC Entra app** (one-time manual step):
      ```bash
      SUB="<your-subscription-id>"; REPO="<owner>/<repo>"
      APP_ID=$(az ad app create --display-name "jenkins-2026-github-oidc" --query appId -o tsv)
      az ad sp create --id "$APP_ID"
      az ad app federated-credential create --id "$APP_ID" --parameters \
        "{\"name\":\"github-gke-production\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"repo:${REPO}:environment:gke-production\",\"audiences\":[\"api://AzureADTokenExchange\"]}"
      az role assignment create --assignee "$APP_ID" --role "Contributor"               --scope "/subscriptions/${SUB}"
      az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "/subscriptions/${SUB}"
      ```

   b. **Set the identifier secrets** (no secret values — just IDs):
      ```bash
      gh secret set AZURE_CLIENT_ID                --body "$APP_ID"
      gh secret set AZURE_TENANT_ID               --body "$(az account show --query tenantId -o tsv)"
      gh secret set AZURE_SUBSCRIPTION_ID         --body "$SUB"
      gh secret set AZURE_GRAFANA_ADMIN_OBJECT_IDS --body "$(az ad signed-in-user show --query id -o tsv)"
      ```

   c. **Run the "Day0.infra.03 Azure managed-grafana" workflow**.

## Running the GKE Workflows

1. Go to the repo's **Actions** tab → **Day1.cluster.01 GKE** → **Run
   workflow**. Pick `observability_mode`. `enable_gateway` defaults to **checked**
   — this project's intended public access path. **Uncheck it only** for a fresh
   environment where the one-time **Day0.infra.01 Gateway bootstrap** + DNS records +
   IAP OAuth client haven't been done yet.
2. Wait ~15-20 minutes. The job summary prints the cluster name/zone and a
   reminder to decommission when done.
3. To redeploy only Jenkins between provision/decommission cycles, use
   **Actions** → **Day2.redeploy.02 Jenkins** → **Run workflow**.
4. When finished, use **Actions** → **Decom.cluster.01 GKE** → **Run workflow**.

All GKE-touching workflows — including the three above, every other
`Day2.redeploy.*`/`Day2.publish.*`/`Day2.scale.*` and the RUM simulator —
share `concurrency: group: jenkins-2026-gke`, so GitHub Actions queues them
rather than letting them race on the same cluster/Terraform state. **Always
run decommission when you're done** — an abandoned cluster keeps billing.

---

[← Previous: 101. GitHub Actions Workflows](./101-GITHUB_ACTIONS_WORKFLOWS.md) | [🏠 Home](../README.md) | [→ Next: 103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md)

---

*102. GitHub Actions Automation — jenkins-2026*
