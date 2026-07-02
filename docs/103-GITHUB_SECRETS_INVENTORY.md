[← Previous: 102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md) | [🏠 Home](../README.md) | [→ Next: 104. Rebuild-Safety](./104-REBUILD_SAFETY.md)

---

# 103 — GitHub Secrets & Variables Inventory

Complete reference for every GitHub Actions secret and repository variable used across [`.github/workflows/`](../.github/workflows). Grouped by subsystem. **Required** = the workflow fails or silently skips its purpose without it. **Optional** = graceful degradation.

> **Quick setup**: see [102 § Setup walkthrough](102-GITHUB_ACTIONS_AUTOMATION.md) for the step-by-step `gh secret set` commands that create these in order.

> **In-cluster Secrets**: these GitHub secrets are the *source* values. For how they
> are materialised into Kubernetes `Secret`s, which namespace each lands in, and why
> (the per-app layout + the IAP replication constraint), see
> [201 § Namespaces & in-cluster Secrets](201-ARCHITECTURE.md#namespaces--in-cluster-secrets).

> **Secrets backend (`secrets.backend`)**: by default (`imperative`) these values
> become k8s Secrets directly via `01-namespaces.sh`. With `secrets.backend=eso`
> they are pushed to **GCP Secret Manager** and synced in by the **External Secrets
> Operator** (keyless, versioned, Cloud-Audit-Logged). See
> [201 § Secrets backend](201-ARCHITECTURE.md#secrets-backend-imperative--eso).

---

## 1. GCP / Core Infrastructure

These four secrets are **required by every GCP-touching workflow**. They are produced in one shot by `terraform apply` inside [`terraform/bootstrap/`](../terraform/bootstrap) (one-time, local state, human-run — see [102 § Bootstrap](102-GITHUB_ACTIONS_AUTOMATION.md)).

| Secret | Type | Required | Source |
|--------|------|----------|--------|
| `GCP_PROJECT_ID` | string | **yes** | `terraform output -raw project_id` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | string | **yes** | `terraform output -raw workload_identity_provider` |
| `GCP_SERVICE_ACCOUNT` | string | **yes** | `terraform output -raw ci_service_account_email` |
| `TF_STATE_BUCKET` | string | **yes** | `terraform output -raw state_bucket` |

**`GCP_PROJECT_ID`**
The GCP project that hosts the GKE cluster, GCS state bucket, and the Workload Identity Pool. Referenced in workflow step summaries and passed as `TF_VAR_project_id` to Terraform.

**`GCP_WORKLOAD_IDENTITY_PROVIDER`**
Full resource name of the Workload Identity Federation provider, e.g. `projects/123/locations/global/workloadIdentityPools/pool/providers/github`. Used by `google-github-actions/auth` to exchange the OIDC token for a GCP access token — **no service account key ever stored**.

**`GCP_SERVICE_ACCOUNT`**
Email of the CI service account impersonated via WIF, e.g. `ci@my-project.iam.gserviceaccount.com`. Its project roles are granted by [`terraform/bootstrap`](../terraform/bootstrap/main.tf) (the authoritative source): `container.admin`, `compute.networkAdmin`, `compute.loadBalancerAdmin`, `iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `resourcemanager.projectIamAdmin`, `serviceusage.serviceUsageAdmin`, **`certificatemanager.owner`** (owner — *not* editor; editor lacks the `.delete` permissions, so the Gateway cert map couldn't be torn down — see [902](./902-TROUBLESHOOTING.md)), **`dns.admin`** (manage the delegated public DNS zone's records in `gateway-bootstrap`), **`secretmanager.admin`** (push secret values to Secret Manager when `secrets.backend=eso`), plus `storage.objectAdmin` on the state bucket and `iam.workloadIdentityUser` for the GitHub WIF binding.

**`TF_STATE_BUCKET`**
Name of the GCS bucket used for Terraform remote state by [`terraform/gke`](../terraform/gke), [`terraform/grafana-cloud-token`](../terraform/grafana-cloud-token), [`terraform/azure-managed-grafana`](../terraform/azure-managed-grafana), and [`terraform/aws-managed-grafana`](../terraform/aws-managed-grafana). Written into `backend_override.tf` at workflow runtime; never committed. Also holds the durable **`jenkins-2026/active-ci-engine`** object: `Day1.cluster.01-gke` writes the deployed CI engine there, and the cluster-decoupled dashboard publishers `Day2.publish.03-azure-grafana` / `Day2.publish.04-aws-grafana` read it (via read-only GCP auth) to gate the off-engine CI overview without needing cluster access.

---

## 2. Grafana Cloud

Used by `observability.mode: grafana-cloud`. The lifecycle workflows (`Day1.cluster.01`, `Decom.cluster.01`) manage the Terraform-provisioned Grafana Cloud stack (data sources, service-account tokens, OTLP credentials); `Day2.publish.05` and `Day2.traffic.01` use these values at runtime.

| Secret / Variable | Type | Required | Scope |
|-------------------|------|----------|-------|
| `GRAFANA_CLOUD_API_TOKEN` | secret | **yes** (grafana-cloud) | stack + token lifecycle |
| `GRAFANA_TRACES_DASHBOARD_UID` | secret | optional | "View trace" link in Jenkins builds |
| `OTEL_LOGS_BACKEND_URL` | secret | optional | logs Explore link in Jenkins builds |

**`GRAFANA_CLOUD_API_TOKEN`**
A Grafana Cloud Access Policy token with scopes: `stacks:read/write/delete`, `accesspolicies:read/write/delete`, `stack-service-accounts:write`, `datasources:read/write`, `pdc:read/write`, `stack-plugins:read/write`. Used by [`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack) (create/destroy the stack) and [`terraform/grafana-cloud-token`](../terraform/grafana-cloud-token) (per-deployment service-account token + OTLP credentials). Created in **Grafana Cloud Portal → Administration → Access Policies**. This is the **only** Grafana Cloud secret you must set — the stack slug is generated by Terraform (see below) and the OTLP endpoint/auth/URL are read at runtime from the in-cluster `grafana-cloud-credentials` Secret.

> **No `GRAFANA_CLOUD_STACK_SLUG` / `GRAFANA_CLOUD_OTLP_ENDPOINT` / `GRAFANA_CLOUD_OTLP_AUTH`.** These were removed. The stack slug is now **generated** (`<prefix><random>`) by [`terraform/grafana-cloud-stack`](../terraform/grafana-cloud-stack) and read by `Day1.cluster.01` from that module's state output, so the stack is ephemeral and a destroy+recreate never collides with Grafana Cloud's reserved-slug cooldown. The OTLP endpoint/auth and Grafana base URL are produced by [`terraform/grafana-cloud-token`](../terraform/grafana-cloud-token) into the `grafana-cloud-credentials` k8s Secret, which `Day2.traffic.01-k6` reads directly (no static fallback). The Grafana Cloud **org/account** (free tier) is created once by hand and is never managed by Terraform.

**`GRAFANA_TRACES_DASHBOARD_UID`**
The Grafana dashboard UID used to construct the "View trace in Grafana" link injected into Jenkins build descriptions by the OTel plugin. Find it in the dashboard URL: `/d/<uid>/...`. If unset, the link is omitted from build descriptions.

**`OTEL_LOGS_BACKEND_URL`**
The full Grafana Logs Explore URL used for the "View logs in Grafana" link from Jenkins builds, e.g. `https://myorg.grafana.net/explore?...`. If unset, the logs link is omitted.

---

## 3. Grafana Alert Email

Used by `Day2.publish.05-alerts` and [`scripts/07.5-grafana-alerts.sh`](../scripts/07.5-grafana-alerts.sh). The script resolves the contact-point email with this priority chain (highest → lowest):

```
GRAFANA_ALERT_EMAIL_<MODE>        ← per-mode secret (grafana-cloud, oss, …)
  └→ GRAFANA_ALERT_EMAIL          ← generic fallback for all modes
       └→ jenkins-credentials.oidc-admin-email   ← cluster default
```

The mode suffix is the uppercased, hyphen-to-underscore form of `observability.mode` from [`config/config.yaml`](../config/config.yaml):

| Secret | Mode | Required |
|--------|------|----------|
| `GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD` | `grafana-cloud` | **yes** if ≠ `JENKINS_OIDC_ADMIN_EMAIL` |
| `GRAFANA_ALERT_EMAIL_OSS` | `oss` | optional |
| `GRAFANA_ALERT_EMAIL_MANAGED_AZURE` | `managed-azure` | optional |
| `GRAFANA_ALERT_EMAIL_MANAGED_AWS` | `managed-aws` | optional |
| `GRAFANA_ALERT_EMAIL` | all modes (fallback) | optional |

**`GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD`**
The email address that receives Grafana Cloud alert notifications. **Must be a member of the Grafana Cloud org** — Grafana Cloud's provisioning API rejects contact points addressed to emails that are not registered org members, even if the email belongs to the account owner. Set this whenever your Grafana Cloud org email differs from `JENKINS_OIDC_ADMIN_EMAIL` (use the same identity you sign in to Grafana Cloud with).
```bash
gh secret set GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD --body "you@example.com"
```
> **Symptom this fixes.** If [`scripts/07.5-grafana-alerts.sh`](../scripts/07.5-grafana-alerts.sh) logs `Grafana API POST /api/v1/provisioning/contact-points → HTTP 400 {"message":"invalid object specification: one or many email addresses specified in the integration are not members of this organization"}`, the resolved alert email is not an org member — set this secret to an org-member address. The run is **not** failed by this: alert *rules* are still provisioned; only the email contact point and notification policy are skipped until the address is valid.

**`GRAFANA_ALERT_EMAIL_OSS` / `GRAFANA_ALERT_EMAIL_MANAGED_AZURE` / `GRAFANA_ALERT_EMAIL_MANAGED_AWS`**
Per-mode overrides for OSS and managed backends. Omit if the correct address is already in `JENKINS_OIDC_ADMIN_EMAIL` (the cluster default).

**`GRAFANA_ALERT_EMAIL`**
Generic fallback used for any mode that has no mode-specific secret set. Omit if `JENKINS_OIDC_ADMIN_EMAIL` is the right address for all modes.

---

## 4. Azure Managed Grafana (`managed-azure` mode)

Used by `Day0.infra.03-azure-grafana`, `Day1.cluster.01-gke`, `Day2.publish.03-azure-grafana`, `Day2.publish.05-alerts`, `Decom.infra.03-azure-grafana`. These are **identifiers only** — no secret credential values. The actual Azure credentials are obtained at runtime via GitHub OIDC federation; no client secret is ever stored.

| Secret | Required | Description |
|--------|----------|-------------|
| `AZURE_CLIENT_ID` | **yes** (managed-azure) | Entra application (client) ID for the GitHub OIDC federated credential |
| `AZURE_TENANT_ID` | **yes** (managed-azure) | Azure Active Directory tenant ID |
| `AZURE_SUBSCRIPTION_ID` | **yes** (managed-azure) | Azure subscription ID |
| `AZURE_GRAFANA_ADMIN_OBJECT_IDS` | **yes** (managed-azure) | Comma-separated Entra object IDs granted the Grafana Admin role on Azure Managed Grafana |

**`AZURE_CLIENT_ID`**
The `appId` of the Entra app created during the one-time azure-bootstrap step (`Day0.infra.03`). The app has a federated credential configured to trust tokens from this repo's `azure-bootstrap` environment. Used by `azure/login@v2` to exchange the OIDC token for an Azure access token — no `AZURE_CLIENT_SECRET` needed.

**`AZURE_GRAFANA_ADMIN_OBJECT_IDS`**
Your own Entra object ID (`az ad signed-in-user show --query id -o tsv`) so you can log into Azure Managed Grafana. Can be a comma-separated list for multiple admins.

See [102 § Azure backend setup](102-GITHUB_ACTIONS_AUTOMATION.md) for the `az` commands that produce all four values.

---

## 5. AWS Managed Grafana (`managed-aws` mode)

Used by `Day0.infra.04-aws-grafana`, `Day1.cluster.01-gke`, `Day2.publish.04-aws-grafana`, `Day2.publish.05-alerts`, `Decom.infra.04-aws-grafana`. All three are **identifiers only** — authentication is via OIDC `AssumeRoleWithWebIdentity`; no access keys stored.

| Secret | Required | Description |
|--------|----------|-------------|
| `AWS_BOOTSTRAP_ROLE_ARN` | **yes** (managed-aws) | IAM role assumed during one-time bootstrap (`Day0.infra.04`) |
| `AWS_REGION` | **yes** (managed-aws) — set as a repo **Variable**, not a Secret | AWS region for AMP, AMG, and CloudWatch, e.g. `eu-west-1`. It is a GitHub Actions **Variable** (`vars.AWS_REGION`), **not** a Secret: the region is not sensitive, and as a Secret GitHub masks its value everywhere it appears — including inside the Amazon Managed Grafana URL (`https://g-….grafana-workspace.***.amazonaws.com`), which broke the clickable link in the Day1 "Access URLs". Workflows read `${{ vars.AWS_REGION \|\| secrets.AWS_REGION }}` (Variable first, Secret only as a legacy fallback). |
| `GKE_OIDC_ISSUER_URL` | **yes** (managed-aws bootstrap) | GKE cluster OIDC issuer URL — used to configure the GKE→AWS OIDC trust |
| `AWS_GRAFANA_ADMIN_SSO_EMAILS` | no (managed-aws) | Comma-separated emails of IAM Identity Center users granted Grafana Admin (`alice@example.com,bob@example.com`) |
| `AWS_DASHBOARD_PUBLISH_ROLE_ARN` | **yes** (managed-aws publishing) | Least-privilege IAM role for dashboard publishing and alert provisioning |

**`AWS_BOOTSTRAP_ROLE_ARN`**
The IAM role with `AdministratorAccess` (or equivalent) created manually before running `Day0.infra.04`. GitHub Actions assumes it via OIDC to run the one-time Terraform that creates AMP, AMG, and the collector's IAM role. Only used by `Day0.infra.04` and `Decom.infra.04`.

**`AWS_GRAFANA_ADMIN_SSO_EMAILS`**
Comma-separated list of email addresses of IAM Identity Center users to grant Grafana Admin on the AMG workspace (e.g. `alice@example.com,bob@example.com`). Passed as `TF_VAR_grafana_admin_sso_emails` in `Day0.infra.04`; Terraform looks up each user in the Identity Store and calls `aws_grafana_role_association`. Optional — leave empty to manage access manually via the console. Users must already exist in IAM Identity Center before the bootstrap runs.

**`GKE_OIDC_ISSUER_URL`**
The OIDC issuer URL of the GKE cluster, e.g. `https://container.googleapis.com/v1/projects/…`. Used by [`terraform/aws-managed-grafana`](../terraform/aws-managed-grafana) to create the OIDC provider that lets the in-cluster OTel collector assume its IAM role via web-identity token projection.

**`AWS_DASHBOARD_PUBLISH_ROLE_ARN`**
IAM role with scoped permissions for `aws grafana create-workspace-api-key` and Grafana API calls. Assumed in CI by `Day2.publish.04` (dashboard publishing) and `Day2.publish.05` (alert provisioning) for day-2 operations without re-running the full provision.

---

## 6. Jenkins OIDC / Google Sign-In

Used by `Day1.cluster.01-gke` (Jenkins JCasC OIDC sign-in). `JENKINS_OIDC_ADMIN_EMAIL` is additionally reused as an admin/notification identity by `Day2.redeploy.01-argocd`, `Day2.redeploy.04-headlamp`, `Day2.redeploy.05-gateway` and `Day2.publish.05-alerts`. Optional — without them Jenkins falls back to the local `admin` account (escape hatch).

| Secret | Required | Description |
|--------|----------|-------------|
| `JENKINS_OIDC_CLIENT_ID` | optional | Google OAuth 2.0 client ID for "Sign in with Google" on Jenkins |
| `JENKINS_OIDC_CLIENT_SECRET` | optional | Google OAuth 2.0 client secret |
| `JENKINS_OIDC_ADMIN_EMAIL` | optional | Google account email granted the Jenkins `admin` role via OIDC |

**`JENKINS_OIDC_ADMIN_EMAIL`**
Stored in the `jenkins-credentials` k8s Secret as `oidc-admin-email`. Also serves as the default Grafana alert notification email for all obs modes (lowest-priority fallback). **Never commit to the repo** — always set via this secret.

Create these in **Google Cloud Console → APIs & Services → OAuth 2.0 Client IDs**. Authorized redirect URI: `https://<jenkins-host>/securityRealm/finishLogin`.

---

## 7. Headlamp & Identity-Aware Proxy

Used by `Day1.cluster.01-gke` and `Day2.redeploy.04-headlamp`. Required only if the Gateway / IAP feature is enabled (`config/config.yaml → gateway.baseDomain`).

| Secret | Required | Description |
|--------|----------|-------------|
| `HEADLAMP_OIDC_CLIENT_ID` | optional | Google OAuth client ID for Headlamp's "Sign in with Google" |
| `HEADLAMP_OIDC_CLIENT_SECRET` | optional | Google OAuth client secret for Headlamp |
| `HEADLAMP_ADMIN_EMAILS` | optional | Comma-separated Google emails granted `cluster-admin` via Headlamp **and** IAP access |
| `IAP_OAUTH_CLIENT_ID` | optional | OAuth client ID for the Identity-Aware Proxy that gates Jenkins and Headlamp |
| `IAP_OAUTH_CLIENT_SECRET` | optional | OAuth client secret for IAP |

**`HEADLAMP_ADMIN_EMAILS`**
Written into the `headlamp-admin-emails` key of `jenkins-credentials` and used both by the Headlamp RBAC ClusterRoleBinding (granting `cluster-admin`) and by the IAP backend-service IAM binding (granting `IAP-secured Web App User`). **Never commit** — set via this secret.

**`IAP_OAUTH_CLIENT_ID` / `IAP_OAUTH_CLIENT_SECRET`**
A separate OAuth client (Backend type) used by GKE's IAP integration. Different from the Headlamp and Jenkins OIDC clients. Created in **Google Cloud Console → Security → Identity-Aware Proxy**.

---

## 8. Private Registry & Git

Used by `Day1.cluster.01-gke` and `Day2.redeploy.04-headlamp`. Needed only if microservice images are pulled from a private registry or the Microservices source repo is private.

| Secret | Required | Description |
|--------|----------|-------------|
| `REGISTRY_USERNAME` | optional | Username for the private container registry (e.g. GitHub PAT for GHCR) |
| `REGISTRY_PASSWORD` | optional | Password / token for the private container registry |
| `GIT_USERNAME` | optional | GitHub username for cloning a private Microservices fork |
| `GIT_TOKEN` | optional | GitHub PAT with `repo` scope for the private Microservices fork |

If left unset, the image pull and git clone steps proceed unauthenticated (works for public repos / public images).

---

## 9. Tekton CI Engine (`ci.engine: tekton`)

Used by `Day1.cluster.01-gke` and `Day2.redeploy.03-tekton` when the Tekton CI engine is selected (`ci.engine: tekton`). Tekton reuses the **existing** registry, git, and IAP secrets — `REGISTRY_USERNAME` / `REGISTRY_PASSWORD` (image push/pull), `GIT_USERNAME` / `GIT_TOKEN` (private Microservices fork), and `IAP_OAUTH_CLIENT_ID` / `IAP_OAUTH_CLIENT_SECRET` (the Tekton Dashboard is gated by the same Google IAP as Headlamp). The only **new** secrets are the two optional webhook HMAC tokens below.

| Secret | Required | Description |
|--------|----------|-------------|
| `TEKTON_GITHUB_WEBHOOK_SECRET` | optional | GitHub HMAC token validating requests to the Tekton Triggers EventListener |
| `PAC_WEBHOOK_SECRET` | optional | GitHub HMAC token validating requests to the Pipelines-as-Code (PaC) controller |

**`TEKTON_GITHUB_WEBHOOK_SECRET`**
A shared-secret HMAC token GitHub signs webhook deliveries with, validated by the Tekton Triggers `EventListener`. Optional — empty by default; only needed if you expose the EventListener webhook so GitHub can trigger PipelineRuns. You generate it yourself (e.g. `openssl rand -hex 20`) and set it as a GitHub Actions secret **and** in the GitHub repo's webhook config. Consumed by `Day1.cluster.01-gke` and `Day2.redeploy.03-tekton`.

**`PAC_WEBHOOK_SECRET`**
The equivalent HMAC token for **Pipelines-as-Code** (the git-driven CI path, the default for the app repos). [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) writes it into the `pac-webhook` Secret (key `webhook.secret`, referenced by [`tekton/pac/repositories.yaml`](../tekton/pac/repositories.yaml)); empty by default, so PaC works unauthenticated until you set it and configure the matching GitHub webhook secret. Generate with `openssl rand -hex 20`. Consumed by `Day1.cluster.01-gke` and `Day2.redeploy.03-tekton`.

---

## 9.5. GitHub Actions / ARC CI Engine (`ci.engine: githubactions`)

Used by `Day1.cluster.01-gke` and `Day2.redeploy.06-githubactions` when the GitHub
Actions CI engine is selected (`ci.engine: githubactions`). ARC (Actions Runner
Controller) registers the in-cluster self-hosted runners with GitHub via a **GitHub
App**; the three secrets below are that App's credentials. [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh)
materialises them into the **`arc-github-app`** Secret in the `arc-runners` namespace
(ESO-synced in `secrets.backend=eso` mode via [`scripts/08.6-eso-sync.sh`](../scripts/08.6-eso-sync.sh)). They are
**only meaningful when `ci_engine=githubactions`**. ARC otherwise reuses the existing
ghcr registry secret (`arc-registry` imagePullSecret) and `GIT_*` env.

| Secret | Required | Description |
|--------|----------|-------------|
| `ARC_GITHUB_APP_ID` | optional | GitHub App **App ID** for the ARC runner-registration App |
| `ARC_GITHUB_APP_INSTALLATION_ID` | optional | The App's **installation ID** on the org/repo |
| `ARC_GITHUB_APP_PRIVATE_KEY` | optional | The App's **private key** (PEM). **Sensitive — a private key.** |

**`ARC_GITHUB_APP_ID` / `ARC_GITHUB_APP_INSTALLATION_ID`**
Non-sensitive identifiers of the ARC GitHub App. Created when you **register the ARC
GitHub App on the org** (GitHub → Settings → Developer settings → GitHub Apps), grant
it the runner-admin permissions ARC needs, and install it. Read the App ID off the
App's page and the installation ID off its install URL.

**`ARC_GITHUB_APP_PRIVATE_KEY`**
The App's generated private key (a `.pem`). **High sensitivity** — treat like any
signing key; never commit. Consumed by `Day1.cluster.01-gke` and
`Day2.redeploy.06-githubactions` → [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) (builds the `arc-github-app`
Secret in `arc-runners`).

> **PAT fallback.** If you skip the GitHub App, ARC can instead authenticate with a
> classic **PAT** supplied as `GIT_TOKEN` (used as the runner-registration
> `github_token`). Either way, when the engine renders `.github/workflows/` into the
> app forks, **`GIT_TOKEN` must additionally carry the `workflow` scope** to push
> workflow files.

### Registering the ARC GitHub App — step by step

ARC's runner **listener** needs an org-admin-level credential to mint *runner
registration tokens* for the org-level scale set (`githubConfigUrl:
https://github.com/nubenetes`). With `githubactions.authMode: app` (the default in
[`config/config.yaml`](../config/config.yaml)), that credential is a **GitHub App**
you register **once** on the org. If the App secrets are absent, `01-namespaces.sh`
falls back to the `GIT_TOKEN` PAT — which usually lacks the runner-admin permission,
so the controller can't register and logs:

```
github api error: StatusCode 403 ... "You must be an org admin or have the
runners and runner groups fine-grained permission."
```

Register the App once:

**1 — Create the App.** Open **`https://github.com/organizations/nubenetes/settings/apps/new`**
(Org → Settings → Developer settings → GitHub Apps → *New GitHub App*) and set:
- **GitHub App name** — any globally-unique name, e.g. `nubenetes-arc-runners`.
- **Description** — *optional and cosmetic* (shown only to people viewing the App in the
  org settings; it does **not** affect ARC). A useful value, so future-you knows what it
  is: *"Actions Runner Controller (ARC) — registers and autoscales the in-cluster
  self-hosted runners for the nubenetes microservices CI (jenkins-2026 GKE cluster,
  `ci.engine=githubactions`)."*
- **Homepage URL** — anything (e.g. `https://github.com/nubenetes/jenkins-2026`).
- **Webhook → Active** — **uncheck it.** The `gha-runner-scale-set` listener is
  *pull-based* (it long-polls the GitHub Actions service), so **no webhook is needed**.
  Leave the Webhook URL blank.
- **Permissions → Organization permissions → Self-hosted runners → Read and write.**
  This is the **only** permission an *org-level* scale set needs — it is exactly the
  "runners and runner groups" permission the 403 above asks for. (Repository →
  *Metadata: Read-only* is added automatically; no other repository permission is
  required for org-level runners.)
- **Where can this GitHub App be installed?** → **Only on this account.**
- Click **Create GitHub App**.

**2 — App ID.** On the App's **General** page, copy the **App ID** (a number) →
`ARC_GITHUB_APP_ID`.

**3 — Private key.** Still on **General**, under **Private keys**, click **Generate a
private key**. A `.pem` downloads; its **full contents** (including the
`-----BEGIN/END … PRIVATE KEY-----` lines) → `ARC_GITHUB_APP_PRIVATE_KEY`. Treat it
like any signing key — never commit it.

**4 — Install the App + read the installation ID.** In the App's left sidebar click
**Install App**, install it on the **`nubenetes`** org, and choose **All repositories**
(or just the microservices forks + `jenkins-2026`).

Now read the **installation ID** — note it is **not** the App ID, and it lives on the
*installation* page, not the App's settings page (the post-install redirect often
doesn't leave you there, which makes it easy to miss). The reliable way is the API
(you must be an org owner):

```bash
gh api orgs/nubenetes/installations \
  --jq '.installations[] | "\(.app_slug): app_id=\(.app_id) installation_id=\(.id)"'
# -> nubenetes-arc-runners: app_id=<APP_ID> installation_id=<INSTALLATION_ID>
```

> **Git Bash on Windows:** omit the leading slash — `orgs/...`, **not** `/orgs/...` —
> or MSYS rewrites the path to `C:/Program Files/Git/orgs/...` and `gh` rejects it.

In the UI instead: **Org → Settings → Third-party Access → GitHub Apps → `Configure`**
next to your App; the browser URL is then
`https://github.com/organizations/nubenetes/settings/installations/<NUMBER>`, and that
trailing `<NUMBER>` is the installation ID → `ARC_GITHUB_APP_INSTALLATION_ID`.

**5 — Store the three secrets** on `nubenetes/jenkins-2026`. The two IDs are plain
`--body` values (any shell); the private key is read **from the `.pem` file**, and how you
feed a file to `gh` **differs by shell**.

App ID + installation ID — any shell:
```bash
gh secret set ARC_GITHUB_APP_ID              --repo nubenetes/jenkins-2026 --body "<app-id>"
gh secret set ARC_GITHUB_APP_INSTALLATION_ID --repo nubenetes/jenkins-2026 --body "<installation-id>"
```
Private key — **Linux / macOS / Git Bash / WSL** (stdin redirection with `<`):
```bash
gh secret set ARC_GITHUB_APP_PRIVATE_KEY --repo nubenetes/jenkins-2026 < ./<app>.private-key.pem
```
Private key — **Windows PowerShell** (PowerShell has **no `<` redirection operator** — it
errors `'<' is reserved for future use` — so pipe the file with `Get-Content -Raw` instead):
```powershell
Get-Content -Raw .\<app>.private-key.pem | gh secret set ARC_GITHUB_APP_PRIVATE_KEY --repo nubenetes/jenkins-2026
```
(Or set all three in the UI: repo → *Settings → Secrets and variables → Actions → New
repository secret* — for the key, paste the full `.pem` including the `-----BEGIN/END-----` lines.)

**6 — Allow your (public) forks to use the runners.** This step is **easy to miss and
will silently break every build if skipped.** GitHub **blocks public repositories from
using self-hosted runners by default** — a pull request from a fork could otherwise run
untrusted code on your runners. The nubenetes microservices forks
(`jhipster-sample-app-gateway`, `jhipster-sample-app-microservice`) are **public**, so
without this the scale set registers perfectly but **workflow runs sit in `queued`
forever**: GitHub never routes their jobs to the runners, and the listener logs
`Calculated target runner count {"assigned job": 0, …}` (no runner pod is ever created).
Enable it once, on the runner group that owns the scale set:

- Open **`https://github.com/organizations/nubenetes/settings/actions/runner-groups`**
  (Org → Settings → Actions → *Runner groups*).
- Open the group that owns `jenkins-2026-runners` — the **Default** group, unless you set
  `githubactions.runnerGroup`.
- Tick **Allow public repositories**.
- Under **Repository access**, choose **All repositories** (or add the microservices forks
  explicitly).
- **Save.**

There is **no secret or config flag for this** — it is a one-time org-admin UI toggle.
(If you instead keep the forks **private**, skip this step: private repos use self-hosted
runners without the toggle.)

**7 — Re-deploy.** `authMode: app` is already the default, so **no config change is
needed**. Re-run `Day1.cluster.01-gke` (or `Day2.redeploy.06-githubactions`):
`01-namespaces.sh` now finds the three secrets and builds the `arc-github-app` Secret
with `github_app_id` / `github_app_installation_id` / `github_app_private_key` (instead
of `github_token`). The controller mints a registration token, the **AutoscalingListener**
pod starts in `arc-systems`, and the `jenkins-2026-runners` scale set registers —
`test/smoke-test.sh`'s *"ARC AutoscalingListener Running"* check then passes. With step 6
done, a `push`/PR to a fork now spins up an ephemeral runner pod in `arc-runners` and the
run executes (visible in that fork's Actions tab — there is no in-cluster CI UI; see
[`404-GITHUB_ACTIONS.md`](./404-GITHUB_ACTIONS.md)).

### Troubleshooting: the runner scale set never registers

Two **distinct** failure modes (both surfaced live the first time `ci.engine=githubactions`
ran — they happen in this order):

1. **No `AutoscalingRunnerSet` is created at all**, and `kubectl -n argocd get application
   arc-runner-scale-set` shows **sync = `Unknown`** with
   `ComparisonError: ... No gha-rs-controller deployment found using label
   (app.kubernetes.io/part-of=gha-rs-controller)`. The `gha-runner-scale-set` chart
   auto-discovers the controller's ServiceAccount with a Helm `lookup`, which ArgoCD's
   `helm template` render **cannot** do (no live cluster), so the whole render fails and
   no manifest is produced. Fixed by setting `controllerServiceAccount.{namespace,name}`
   explicitly in
   [`argocd/githubactions/templates/runner-scale-set.yaml`](../argocd/githubactions/templates/runner-scale-set.yaml).
   Verify: the app should be `Synced` and `kubectl get autoscalingrunnerset -A` should
   list `jenkins-2026-runners`.

2. **The `AutoscalingRunnerSet` exists but no listener pod starts**, and
   `kubectl -n arc-systems logs deploy/arc-gha-rs-controller | grep -i 403` shows
   **`403 … "You must be an org admin or have the runners and runner groups fine-grained
   permission."`** That's *this* section — the credential lacks the org runner-admin
   permission. Register the GitHub App above, **or** grant the `GIT_TOKEN` PAT the
   **Organization → Self-hosted runners → Read and write** fine-grained permission (classic
   scope: `admin:org`) and set `githubactions.authMode: pat`.

### Troubleshooting: registered, but workflow runs sit in `queued` forever

The listener **is** Running (`kubectl -n arc-systems get pods | grep listener`) and the
controller log is 403-free, yet runs in the forks stay `queued` and **no runner pod** appears
in `arc-runners`. The tell is the controller/listener log line `Calculated target runner count
{"assigned job": 0, …}`: registration succeeded, but GitHub is **not routing the jobs to the
scale set**.

The usual cause is **public repositories**. GitHub **blocks public repos from using
self-hosted runners by default** — a pull request from a fork could otherwise run untrusted
code on your runners. The nubenetes microservices forks (`jhipster-sample-app-gateway`,
`jhipster-sample-app-microservice`) are **public**, so this bites on first use. **Fix (org
admin — a one-time UI toggle; there is no secret or API field for it):** *Organization →
Settings → Actions → Runner groups →* open the group that holds `jenkins-2026-runners` (the
**Default** group, unless you set `githubactions.runnerGroup`) *→* enable **"Allow public
repositories"**, and make sure *Repository access* is **All repositories** (or explicitly
lists the forks). The queued jobs are picked up within ~1 minute — an ephemeral runner pod
appears in `arc-runners` and the run flips to *in_progress*. (Making the forks private is the
alternative, but they are deliberately public demo forks.)

---

## 9.6. Argo Workflows CI Engine (`ci.engine: argoworkflows`)

Used by `Day1.cluster.01-gke` and `Day2.redeploy.07-argoworkflows` when the Argo
Workflows CI engine is selected (`ci.engine: argoworkflows`). Argo Workflows + Argo
Events reuses the **existing** registry, git, and IAP secrets — `REGISTRY_USERNAME` /
`REGISTRY_PASSWORD` (image push/pull), `GIT_USERNAME` / `GIT_TOKEN` (private
Microservices fork), and `IAP_OAUTH_CLIENT_ID` / `IAP_OAUTH_CLIENT_SECRET` (the Argo
Workflows Server UI is gated by the same Google IAP as Headlamp). The only **new**
secret is the one optional webhook HMAC token below.

| Secret | Required | Description |
|--------|----------|-------------|
| `ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET` | optional | GitHub HMAC token validating requests to the Argo Events EventSource (GitHub webhook receiver) |

**`ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET`**
A shared-secret HMAC token GitHub signs webhook deliveries with, validated by the Argo
Events GitHub **EventSource** (the public, no-IAP receiver at `argo-events.<domain>`).
**Low/medium sensitivity** — a shared HMAC, not a private key. Optional: you generate it
yourself (e.g. `openssl rand -hex 20`) and set it as a GitHub Actions secret **and** in
the GitHub repo's webhook config. [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) seeds it into the
`argoworkflows-github-webhook` Secret in the `argo-events` namespace (ESO-synced in
`secrets.backend=eso` mode via [`scripts/08.6-eso-sync.sh`](../scripts/08.6-eso-sync.sh)); if absent,
[`scripts/06-argoworkflows-pipelines.sh`](../scripts/06-argoworkflows-pipelines.sh) generates one (falling back to
`PAC_WEBHOOK_SECRET`). Consumed by `Day1.cluster.01-gke` and
`Day2.redeploy.07-argoworkflows`.

---

## 10. Grafana Cloud k6 (the k6-app) — optional

The k6 smoke pipeline always exports request metrics via **OTLP** to your Grafana
Prometheus (the `k6-smoke-overview` dashboard). **Optionally**, it can *also* stream
each run to **Grafana Cloud k6** (the native k6 app at `/a/k6-app`) for k6's own UI
(per-run trends, run comparison, thresholds, URL breakdown). This is **off by
default** and only activates when **both** secrets below are set; the pipeline then
adds `--out cloud` alongside the OTLP output.

| Secret | Required | Description |
|--------|----------|-------------|
| `K6_CLOUD_TOKEN` | optional | Grafana Cloud k6 API token (the k6-app → settings, or a stack access policy token with k6 write). Sensitive. |
| `K6_CLOUD_PROJECT_ID` | optional | The numeric project id from `/a/k6-app/projects` runs are uploaded to. Not sensitive. |

**`K6_CLOUD_TOKEN`**
Authenticates `k6 run --out cloud` to Grafana Cloud k6. Get it from the k6 app's
token/settings page (or a stack access policy token scoped to k6). Empty by default.

**`K6_CLOUD_PROJECT_ID`**
The project under which runs appear in the k6 app. Both flow into the cluster via
[`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) — a `k6-cloud` Secret in each
active engine's pipeline namespace (the Tekton pipeline ns read by
[`tekton/tasks/k6-smoke.yaml`](../tekton/tasks/k6-smoke.yaml), plus the `arc-runners`
and `argo-ci` equivalents for the GitHub Actions/ARC and Argo Workflows engines) and the
`jenkins-credentials` Secret keys `k6-cloud-token`/`k6-cloud-project-id` (surfaced to
`microservicesK6Smoke.groovy` via [`helm/jenkins/values-common.yaml`](../helm/jenkins/values-common.yaml)
`containerEnv`). Consumed by `Day1.cluster.01-gke` and the per-engine
`Day2.redeploy.*` workflow. The runner/agent needs HTTPS egress to Grafana Cloud k6's
ingest. Works for **all four** CI engines.

---

## Summary table

| Secret / Variable | Sensitive | Required for | Set by |
|---|---|---|---|
| `GCP_PROJECT_ID` | no | all workflows | [`terraform/bootstrap`](../terraform/bootstrap) output |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | yes | all workflows | [`terraform/bootstrap`](../terraform/bootstrap) output |
| `GCP_SERVICE_ACCOUNT` | no | all workflows | [`terraform/bootstrap`](../terraform/bootstrap) output |
| `TF_STATE_BUCKET` | no | all workflows | [`terraform/bootstrap`](../terraform/bootstrap) output |
| `GRAFANA_CLOUD_API_TOKEN` | **yes** | grafana-cloud stack + token lifecycle | Grafana Cloud Portal |
| `GRAFANA_TRACES_DASHBOARD_UID` | no | Jenkins build links | manual |
| `OTEL_LOGS_BACKEND_URL` | no | Jenkins build links | manual |
| `GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD` | no | grafana-cloud alerts | manual |
| `GRAFANA_ALERT_EMAIL_OSS` | no | oss alerts override | manual |
| `GRAFANA_ALERT_EMAIL_MANAGED_AZURE` | no | azure alerts override | manual |
| `GRAFANA_ALERT_EMAIL_MANAGED_AWS` | no | aws alerts override | manual |
| `GRAFANA_ALERT_EMAIL` | no | all-mode alert fallback | manual |
| `K6_CLOUD_TOKEN` | **yes** | optional Grafana Cloud k6 (k6-app) streaming | Grafana Cloud k6 app |
| `K6_CLOUD_PROJECT_ID` | no | optional Grafana Cloud k6 (k6-app) streaming | Grafana Cloud k6 app |
| `AZURE_CLIENT_ID` | no | managed-azure | `az ad app create` |
| `AZURE_TENANT_ID` | no | managed-azure | `az account show` |
| `AZURE_SUBSCRIPTION_ID` | no | managed-azure | `az account show` |
| `AZURE_GRAFANA_ADMIN_OBJECT_IDS` | no | managed-azure | `az ad signed-in-user show` |
| `AWS_BOOTSTRAP_ROLE_ARN` | no | managed-aws bootstrap | manual (IAM console) |
| `AWS_REGION` (repo **Variable**, not a Secret) | no | managed-aws | manual |
| `GKE_OIDC_ISSUER_URL` | no | managed-aws bootstrap | GKE cluster details |
| `AWS_DASHBOARD_PUBLISH_ROLE_ARN` | no | managed-aws day-2 ops | [`terraform/aws-managed-grafana`](../terraform/aws-managed-grafana) output |
| `JENKINS_OIDC_CLIENT_ID` | no | Jenkins Google login | Google Cloud Console |
| `JENKINS_OIDC_CLIENT_SECRET` | **yes** | Jenkins Google login | Google Cloud Console |
| `JENKINS_OIDC_ADMIN_EMAIL` | no | Jenkins admin + alert default | manual — **never commit** |
| `HEADLAMP_OIDC_CLIENT_ID` | no | Headlamp Google login | Google Cloud Console |
| `HEADLAMP_OIDC_CLIENT_SECRET` | **yes** | Headlamp Google login | Google Cloud Console |
| `HEADLAMP_ADMIN_EMAILS` | no | Headlamp RBAC + IAP | manual — **never commit** |
| `IAP_OAUTH_CLIENT_ID` | no | IAP gateway | Google Cloud Console |
| `IAP_OAUTH_CLIENT_SECRET` | **yes** | IAP gateway | Google Cloud Console |
| `REGISTRY_USERNAME` | no | private image pull | manual |
| `REGISTRY_PASSWORD` | **yes** | private image pull | manual |
| `GIT_USERNAME` | no | private microservices fork | manual |
| `GIT_TOKEN` | **yes** | private microservices fork | manual |
| `TEKTON_GITHUB_WEBHOOK_SECRET` | **yes** | Tekton EventListener webhook (`ci.engine=tekton`, optional) | manual — `openssl rand` |
| `PAC_WEBHOOK_SECRET` | **yes** | Pipelines-as-Code webhook (`ci.engine=tekton`, optional) | manual — `openssl rand` |
| `ARC_GITHUB_APP_ID` | no | ARC runner registration (`ci.engine=githubactions`; PAT fallback via `GIT_TOKEN`) | GitHub App registration |
| `ARC_GITHUB_APP_INSTALLATION_ID` | no | ARC runner registration (`ci.engine=githubactions`; PAT fallback via `GIT_TOKEN`) | GitHub App registration |
| `ARC_GITHUB_APP_PRIVATE_KEY` | **yes** | ARC runner registration (`ci.engine=githubactions`; PAT fallback via `GIT_TOKEN`) | GitHub App registration |
| `ARGOWORKFLOWS_GITHUB_WEBHOOK_SECRET` | low/medium | Argo Events GitHub webhook EventSource (`ci.engine=argoworkflows`, optional; `PAC_WEBHOOK_SECRET` fallback) | manual — `openssl rand` |

---

[← Previous: 102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md) | [🏠 Home](../README.md) | [→ Next: 104. Rebuild-Safety](./104-REBUILD_SAFETY.md)

---

*103. GitHub Secrets & Variables Inventory — jenkins-2026*
