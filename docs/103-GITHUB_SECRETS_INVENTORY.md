<!-- PREV: [102 GitHub Actions Automation](102-GITHUB_ACTIONS_AUTOMATION.md) | NEXT: [201 Architecture](201-ARCHITECTURE.md) -->

# 103 — GitHub Secrets & Variables Inventory

Complete reference for every GitHub Actions secret and repository variable used across `.github/workflows/`. Grouped by subsystem. **Required** = the workflow fails or silently skips its purpose without it. **Optional** = graceful degradation.

> **Quick setup**: see [102 § Setup walkthrough](102-GITHUB_ACTIONS_AUTOMATION.md) for the step-by-step `gh secret set` commands that create these in order.

---

## 1. GCP / Core Infrastructure

These four secrets are **required by every GCP-touching workflow**. They are produced in one shot by `terraform apply` inside `terraform/bootstrap/` (one-time, local state, human-run — see [102 § Bootstrap](102-GITHUB_ACTIONS_AUTOMATION.md)).

| Secret | Type | Required | Source |
|--------|------|----------|--------|
| `GCP_PROJECT_ID` | string | **yes** | `terraform output -raw project_id` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | string | **yes** | `terraform output -raw workload_identity_provider` |
| `GCP_SERVICE_ACCOUNT` | string | **yes** | `terraform output -raw ci_service_account_email` |
| `TF_STATE_BUCKET` | string | **yes** | `terraform output -raw state_bucket` |

**`GCP_PROJECT_ID`**
The GCP project that hosts the GKE cluster, GCS state bucket, and the Workload Identity Pool. Referenced in workflow step summaries and passed as `TF_VAR_project_id` to Terraform.

**`GCP_WORKLOAD_IDENTITY_PROVIDER`**
Full resource name of the Workload Identity Federation provider, e.g. `projects/123/locations/global/workloadIdentityPools/pool/providers/github`. Used by `google-github-actions/auth` to exchange the OIDC token for a GCP access token — no service account key ever stored.

**`GCP_SERVICE_ACCOUNT`**
Email of the CI service account impersonated via WIF, e.g. `ci@my-project.iam.gserviceaccount.com`. Needs roles: `container.admin`, `storage.admin`, `iam.serviceAccountTokenCreator`.

**`TF_STATE_BUCKET`**
Name of the GCS bucket used for Terraform remote state by `terraform/gke`, `terraform/grafana-cloud-token`, `terraform/azure-managed-grafana`, and `terraform/aws-managed-grafana`. Written into `backend_override.tf` at workflow runtime; never committed.

---

## 2. Grafana Cloud

Used by `observability.mode: grafana-cloud`. The lifecycle workflows (`0.2.01`, `9.1.01`) manage the Terraform-provisioned Grafana Cloud stack (data sources, service-account tokens, OTLP credentials); `5.1.05` and `5.9.01` use these values at runtime.

| Secret / Variable | Type | Required | Scope |
|-------------------|------|----------|-------|
| `GRAFANA_CLOUD_API_TOKEN` | secret | **yes** (grafana-cloud) | lifecycle management |
| `GRAFANA_CLOUD_STACK_SLUG` | **variable** *(or secret)* | **yes** (grafana-cloud) | lifecycle + runtime |
| `GRAFANA_CLOUD_OTLP_ENDPOINT` | secret | optional | `5.9.01` k6 fallback only |
| `GRAFANA_CLOUD_OTLP_AUTH` | secret | optional | `5.9.01` k6 fallback only |
| `GRAFANA_TRACES_DASHBOARD_UID` | secret | optional | "View trace" link in Jenkins builds |
| `OTEL_LOGS_BACKEND_URL` | secret | optional | logs Explore link in Jenkins builds |

**`GRAFANA_CLOUD_API_TOKEN`**
A Grafana Cloud Access Policy token with scopes: `stacks:read/write/delete`, `accesspolicies:read/write/delete`, `stack-service-accounts:write`, `datasources:read/write`, `pdc:read/write`, `stack-plugins:read/write`. Used by `terraform/grafana-cloud-token` to provision the per-deployment service-account token and OTLP credentials. Created in **Grafana Cloud Portal → Administration → Access Policies**.

**`GRAFANA_CLOUD_STACK_SLUG`** *(recommended as a Repository **Variable**, not a secret)*
The globally-unique slug of your Grafana Cloud stack, e.g. `myorgmonitoring`. Used to construct the Grafana base URL (`https://<slug>.grafana.net`) and passed as `TF_VAR_stack_slug`. Not a sensitive value — store as a variable (`gh variable set`) so it is visible in workflow logs. The workflows also accept it as a secret for backward compatibility (`vars.GRAFANA_CLOUD_STACK_SLUG || secrets.GRAFANA_CLOUD_STACK_SLUG`).
```bash
gh variable set GRAFANA_CLOUD_STACK_SLUG --body "<your-slug>"
```

**`GRAFANA_CLOUD_OTLP_ENDPOINT`**
The OTLP/HTTP endpoint for direct telemetry ingestion, e.g. `https://otlp-gateway-prod-eu-west-0.grafana.net/otlp`. Only used by `5.9.01-traffic-simulation` as a fallback when the GKE cluster is unreachable (normally the value is read from the `grafana-cloud-credentials` k8s Secret). Can be left unset if you always run traffic simulation against a live cluster.

**`GRAFANA_CLOUD_OTLP_AUTH`**
Base64-encoded `<instanceId>:<token>` for the OTLP endpoint's Basic auth header. Same fallback purpose as `GRAFANA_CLOUD_OTLP_ENDPOINT` in `5.9.01`.

**`GRAFANA_TRACES_DASHBOARD_UID`**
The Grafana dashboard UID used to construct the "View trace in Grafana" link injected into Jenkins build descriptions by the OTel plugin. Find it in the dashboard URL: `/d/<uid>/...`. If unset, the link is omitted from build descriptions.

**`OTEL_LOGS_BACKEND_URL`**
The full Grafana Logs Explore URL used for the "View logs in Grafana" link from Jenkins builds, e.g. `https://myorg.grafana.net/explore?...`. If unset, the logs link is omitted.

---

## 3. Grafana Alert Email

Used by `5.1.05-publish-grafana-alerts` and `scripts/07.5-grafana-alerts.sh`. The script resolves the contact-point email with this priority chain (highest → lowest):

```
GRAFANA_ALERT_EMAIL_<MODE>        ← per-mode secret (grafana-cloud, oss, …)
  └→ GRAFANA_ALERT_EMAIL          ← generic fallback for all modes
       └→ jenkins-credentials.oidc-admin-email   ← cluster default
```

The mode suffix is the uppercased, hyphen-to-underscore form of `observability.mode` from `config/config.yaml`:

| Secret | Mode | Required |
|--------|------|----------|
| `GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD` | `grafana-cloud` | **yes** if ≠ `JENKINS_OIDC_ADMIN_EMAIL` |
| `GRAFANA_ALERT_EMAIL_OSS` | `oss` | optional |
| `GRAFANA_ALERT_EMAIL_MANAGED_AZURE` | `managed-azure` | optional |
| `GRAFANA_ALERT_EMAIL_MANAGED_AWS` | `managed-aws` | optional |
| `GRAFANA_ALERT_EMAIL` | all modes (fallback) | optional |

**`GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD`**
The email address that receives Grafana Cloud alert notifications. **Must be a member of the Grafana Cloud org** — Grafana Cloud's provisioning API rejects contact points addressed to emails that are not registered org members, even if the email belongs to the account owner. Set this whenever your Grafana Cloud org email differs from `JENKINS_OIDC_ADMIN_EMAIL`.
```bash
gh secret set GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD --body "you@example.com"
```

**`GRAFANA_ALERT_EMAIL_OSS` / `GRAFANA_ALERT_EMAIL_MANAGED_AZURE` / `GRAFANA_ALERT_EMAIL_MANAGED_AWS`**
Per-mode overrides for OSS and managed backends. Omit if the correct address is already in `JENKINS_OIDC_ADMIN_EMAIL` (the cluster default).

**`GRAFANA_ALERT_EMAIL`**
Generic fallback used for any mode that has no mode-specific secret set. Omit if `JENKINS_OIDC_ADMIN_EMAIL` is the right address for all modes.

---

## 4. Azure Managed Grafana (`managed-azure` mode)

Used by `0.1.03-azure-bootstrap`, `0.2.01-gke-provision`, `5.1.03-publish-azure-dashboards`, `5.1.05-publish-grafana-alerts`, `9.2.03-azure-decommission`. These are **identifiers only** — no secret credential values. The actual Azure credentials are obtained at runtime via GitHub OIDC federation; no client secret is ever stored.

| Secret | Required | Description |
|--------|----------|-------------|
| `AZURE_CLIENT_ID` | **yes** (managed-azure) | Entra application (client) ID for the GitHub OIDC federated credential |
| `AZURE_TENANT_ID` | **yes** (managed-azure) | Azure Active Directory tenant ID |
| `AZURE_SUBSCRIPTION_ID` | **yes** (managed-azure) | Azure subscription ID |
| `AZURE_GRAFANA_ADMIN_OBJECT_IDS` | **yes** (managed-azure) | Comma-separated Entra object IDs granted the Grafana Admin role on Azure Managed Grafana |

**`AZURE_CLIENT_ID`**
The `appId` of the Entra app created during the one-time azure-bootstrap step (`0.1.03`). The app has a federated credential configured to trust tokens from this repo's `azure-bootstrap` environment. Used by `azure/login@v2` to exchange the OIDC token for an Azure access token — no `AZURE_CLIENT_SECRET` needed.

**`AZURE_GRAFANA_ADMIN_OBJECT_IDS`**
Your own Entra object ID (`az ad signed-in-user show --query id -o tsv`) so you can log into Azure Managed Grafana. Can be a comma-separated list for multiple admins.

See [102 § Azure backend setup](102-GITHUB_ACTIONS_AUTOMATION.md) for the `az` commands that produce all four values.

---

## 5. AWS Managed Grafana (`managed-aws` mode)

Used by `0.1.04-aws-bootstrap`, `0.2.01-gke-provision`, `5.1.04-publish-aws-dashboards`, `5.1.05-publish-grafana-alerts`, `9.2.04-aws-decommission`. All three are **identifiers only** — authentication is via OIDC `AssumeRoleWithWebIdentity`; no access keys stored.

| Secret | Required | Description |
|--------|----------|-------------|
| `AWS_BOOTSTRAP_ROLE_ARN` | **yes** (managed-aws) | IAM role assumed during one-time bootstrap (`0.1.04`) |
| `AWS_REGION` | **yes** (managed-aws) | AWS region for AMP, AMG, and CloudWatch, e.g. `eu-west-1` |
| `GKE_OIDC_ISSUER_URL` | **yes** (managed-aws bootstrap) | GKE cluster OIDC issuer URL — used to configure the GKE→AWS OIDC trust |
| `AWS_DASHBOARD_PUBLISH_ROLE_ARN` | **yes** (managed-aws publishing) | Least-privilege IAM role for dashboard publishing and alert provisioning |

**`AWS_BOOTSTRAP_ROLE_ARN`**
The IAM role with `AdministratorAccess` (or equivalent) created manually before running `0.1.04`. GitHub Actions assumes it via OIDC to run the one-time Terraform that creates AMP, AMG, and the collector's IAM role. Only used by `0.1.04` and `9.2.04`.

**`GKE_OIDC_ISSUER_URL`**
The OIDC issuer URL of the GKE cluster, e.g. `https://container.googleapis.com/v1/projects/…`. Used by `terraform/aws-managed-grafana` to create the OIDC provider that lets the in-cluster OTel collector assume its IAM role via web-identity token projection.

**`AWS_DASHBOARD_PUBLISH_ROLE_ARN`**
IAM role with scoped permissions for `aws grafana create-workspace-api-key` and Grafana API calls. Assumed in CI by `5.1.04` (dashboard publishing) and `5.1.05` (alert provisioning) for day-2 operations without re-running the full provision.

---

## 6. Jenkins OIDC / Google Sign-In

Used by `0.2.01-gke-provision` and `5.2.02-redeploy-jenkins`. Optional — without them Jenkins falls back to the local `admin` account (escape hatch).

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

Used by `0.2.01-gke-provision` and `5.2.03-redeploy-headlamp`. Required only if the Gateway / IAP feature is enabled (`config/config.yaml → gateway.baseDomain`).

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

Used by `0.2.01-gke-provision` and `5.2.03-redeploy-headlamp`. Needed only if microservice images are pulled from a private registry or the Microservices source repo is private.

| Secret | Required | Description |
|--------|----------|-------------|
| `REGISTRY_USERNAME` | optional | Username for the private container registry (e.g. GitHub PAT for GHCR) |
| `REGISTRY_PASSWORD` | optional | Password / token for the private container registry |
| `GIT_USERNAME` | optional | GitHub username for cloning a private Microservices fork |
| `GIT_TOKEN` | optional | GitHub PAT with `repo` scope for the private Microservices fork |

If left unset, the image pull and git clone steps proceed unauthenticated (works for public repos / public images).

---

## Summary table

| Secret / Variable | Sensitive | Required for | Set by |
|---|---|---|---|
| `GCP_PROJECT_ID` | no | all workflows | `terraform/bootstrap` output |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | yes | all workflows | `terraform/bootstrap` output |
| `GCP_SERVICE_ACCOUNT` | no | all workflows | `terraform/bootstrap` output |
| `TF_STATE_BUCKET` | no | all workflows | `terraform/bootstrap` output |
| `GRAFANA_CLOUD_API_TOKEN` | **yes** | grafana-cloud lifecycle | Grafana Cloud Portal |
| `GRAFANA_CLOUD_STACK_SLUG` | no | grafana-cloud | manual (`gh variable set`) |
| `GRAFANA_CLOUD_OTLP_ENDPOINT` | no | k6 fallback only | manual |
| `GRAFANA_CLOUD_OTLP_AUTH` | **yes** | k6 fallback only | manual |
| `GRAFANA_TRACES_DASHBOARD_UID` | no | Jenkins build links | manual |
| `OTEL_LOGS_BACKEND_URL` | no | Jenkins build links | manual |
| `GRAFANA_ALERT_EMAIL_GRAFANA_CLOUD` | no | grafana-cloud alerts | manual |
| `GRAFANA_ALERT_EMAIL_OSS` | no | oss alerts override | manual |
| `GRAFANA_ALERT_EMAIL_MANAGED_AZURE` | no | azure alerts override | manual |
| `GRAFANA_ALERT_EMAIL_MANAGED_AWS` | no | aws alerts override | manual |
| `GRAFANA_ALERT_EMAIL` | no | all-mode alert fallback | manual |
| `AZURE_CLIENT_ID` | no | managed-azure | `az ad app create` |
| `AZURE_TENANT_ID` | no | managed-azure | `az account show` |
| `AZURE_SUBSCRIPTION_ID` | no | managed-azure | `az account show` |
| `AZURE_GRAFANA_ADMIN_OBJECT_IDS` | no | managed-azure | `az ad signed-in-user show` |
| `AWS_BOOTSTRAP_ROLE_ARN` | no | managed-aws bootstrap | manual (IAM console) |
| `AWS_REGION` | no | managed-aws | manual |
| `GKE_OIDC_ISSUER_URL` | no | managed-aws bootstrap | GKE cluster details |
| `AWS_DASHBOARD_PUBLISH_ROLE_ARN` | no | managed-aws day-2 ops | `terraform/aws-managed-grafana` output |
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

---

<!-- PREV: [102 GitHub Actions Automation](102-GITHUB_ACTIONS_AUTOMATION.md) | NEXT: [201 Architecture](201-ARCHITECTURE.md) -->
