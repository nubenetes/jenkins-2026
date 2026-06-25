[← Previous: 901. Local Development](./901-LOCAL_DEVELOPMENT.md) | [🏠 Home](../README.md)

---

# 902. Troubleshooting

## Common Issues

- **`yq` not found**: install [`mikefarah/yq`](https://github.com/mikefarah/yq) (the Go binary — not the Python `yq` wrapper around `jq`).

- **`scripts/03-observability.sh` fails with "Secret ... not found"**: create `observability/otel-collector/secret.yaml` from the `.example` template and `kubectl apply` it (see [901. Quick start](./901-LOCAL_DEVELOPMENT.md)) before re-running.

- **Microservices pods stuck in `ImagePullBackOff`**: expected before any pipeline has run for that service. Check `kubectl -n microservices describe pod <pod>` to confirm it's an image-pull issue, then trigger that service's job in Jenkins.

- **Re-running after a partial failure**: every step is idempotent; just re-run `./scripts/up.sh` (or the individual `scripts/0N-*.sh`). Logs from the last `up.sh`/`down.sh` run are under `logs/`.

- **Rotating the Jenkins admin password**: delete the `jenkins-credentials` Secret in the `jenkins` namespace and re-run `scripts/01-namespaces.sh` + `scripts/04-jenkins.sh`.

- **Tekton CI dashboard panels show "No data" on a fresh cluster**: expected until a `PipelineRun` has actually run. The run-scoped metrics (`tekton_pipelines_controller_pipelinerun_total` / `_duration_seconds` / `taskrun_total` / `taskruns_pod_latency`) are only created by the controller **after** the first run; before that those panels are empty even though the scrape works (`up{job="tekton-pipelines-controller"}` = 1, `tekton_pipelines_controller_running_pipelineruns` = 0). With Pipelines-as-Code (default when the gateway is enabled), `Day1` sets PaC up but does **not** trigger a build — it waits for a `git push` to the microservices fork. Trigger one (PaC push, the Tekton Dashboard's *Create*, or `kubectl create` a PipelineRun — see [403 § Running a pipeline by hand](./403-TEKTON.md#running-a-pipeline-by-hand-dashboard--kubectl--tkn)) and the panels populate. Same applies to the trace/span-metrics panels (they need a run to emit traces).

## Dataplane V2 enforcement & fresh-cluster stalls

The cluster runs GKE Dataplane V2 (Cilium/eBPF), so NetworkPolicies actually enforce (see [501 § Zero-Trust](./501-PLATFORM_OPERATIONS.md)). A few things look like failures but are expected/self-healing:

- **`microservices-stable` shows ArgoCD health `Unknown` (even when everything works)**: expected, not a failure. ArgoCD has no health assessment for the CloudNativePG `Cluster`/`Pooler` and OpenTelemetry `Instrumentation` CRs the app owns, so the aggregate app health stays `Unknown` while the actual workloads are fine. Verify with `kubectl -n microservices get deploy` (gateway + jhipster `Available`). `scripts/up.sh` therefore gates the pre-OTel-injection wait on the **Deployments becoming Available**, not on app health (waiting on `Healthy` used to burn the full 10-minute timeout every run).

- **`tekton-pipelines` ArgoCD app `SyncFailed` with `config.webhook.pipeline.tekton.dev` / `tls: unrecognized name` / `x509`**: the Tekton webhook self-issues its serving cert, and on a fresh cluster ArgoCD can first-sync the Tekton config ConfigMaps before that cert exists. This **self-heals**, no manual step: the `tekton-pipelines` app has `syncPolicy.retry` (auto-retry with backoff) so the sync converges once the webhook is up, and it **no longer uses `Replace=true`** — `Replace` used to `kubectl replace` every object on each sync, which re-triggered the webhook and blanked the caBundle (that was also why a **manual** Sync failed even while the app showed Synced/Healthy). If you ever want to force it: `kubectl -n tekton-pipelines rollout restart deploy/tekton-pipelines-webhook`.

- **`gateway` CrashLoop / Liquibase connect-timeout, or pods never Ready**: under enforcement the app needs explicit allows the app chart's own policies miss — egress to CNPG Postgres (by `cnpg.io/cluster`, port 5432) and to the API server (443, for JHipster's Hazelcast discovery). These are carried by the additive `microservices-cnpg-platform` policy in [`infrastructure/networkpolicies.yaml`](../infrastructure/networkpolicies.yaml); confirm it's applied (`kubectl -n microservices get netpol`).

- **A Gateway-exposed UI is unreachable / its GKE backend is `UNHEALTHY`** (argocd, headlamp, …): the NetworkPolicy ingress must allow the **pod** `targetPort` (e.g. argocd-server `8080`, headlamp `4466`), not the Service port — the container-native LB (NEG) sends to the pod port. See the [501 enforcement-gotchas block](./501-PLATFORM_OPERATIONS.md).

## Switching `observability.mode` on a running cluster

Re-running `Day1` (or `scripts/03-observability.sh`) with a different `observability.mode` converges the **same** cluster onto the new backend; each mode branch retires the other modes' agents so the switch is idempotent. Two things that previously bit on a switch (now handled):

- **`k8s-monitoring` install fails: "A Node Exporter already appears to be running ... host port conflict" (9100)** — switching `oss` → `grafana-cloud`/`managed-*` left the OSS `kube-prometheus-stack` node-exporter DaemonSet (hostPort 9100, via ArgoCD) running while the new mode installed its own. ArgoCD's cascade-prune is async, so it raced the install. `remove_oss_observability_app` now **waits** for that DaemonSet to disappear (with a direct-delete backstop) before the new exporter is installed. If you ever hit it manually: `kubectl delete application observability-oss -n argocd --wait=false; kubectl delete ds -n observability -l app.kubernetes.io/name=prometheus-node-exporter`.

- **Wrong CI-overview dashboard lingers (e.g. "Jenkins CI Overview" on a `ci.engine=tekton` cluster)** — Grafana Cloud / Azure Managed Grafana stacks are **persistent**, and `gcx push` / `POST /api/dashboards/db` only upsert, so a previously-published off-engine dashboard survived an engine switch. `scripts/07-grafana-dashboards.sh` now **deletes the inactive engine's overview by UID** in every mode (grafana-cloud, managed-azure, managed-aws; oss drops it at render time). To remove a stale one by hand: `curl -X DELETE "$GRAFANA_BASE_URL/api/dashboards/uid/jenkins2026-jenkins-overview" -H "Authorization: Bearer $GRAFANA_API_KEY"`.

## ArgoCD OIDC Issues

**ArgoCD OIDC Login fails with `redirect_uri_mismatch` or `Invalid redirect URL`**:
- Ensure the GKE cluster was provisioned with `enable_gateway: true` in GitHub Actions. If the gateway is disabled, redirect URLs in `argocd-cm` will fallback to localhost or empty domains, breaking OIDC.
- Verify that `https://argocd.<baseDomain>/api/dex/callback` is added to your Google OAuth client in the GCP Console.
- If you terminate TLS at the gateway and route traffic over HTTP to the backend `argocd-server`, ensure that the `url` field in `argocd-cm` is set to `https://...` (without trailing slash) and the server runs in `--insecure` mode so it trusts the `X-Forwarded-Proto: https` header sent by Google Cloud Load Balancer.

**ArgoCD installation stuck in `pending-install`**: The `scripts/08.5-argocd.sh` script includes recovery logic to detect and clear stuck Helm releases. If it hangs, the script will automatically attempt to `helm uninstall` and retry.

**Gateway resource mapping errors (`GCPBackendPolicy` / `HealthCheckPolicy`)**: Ensure you are using `networking.gke.io/v1` as the API version in `scripts/09-gateway.sh` (already fixed in `main`/`develop`).

## Terraform & CI Issues

**`test/e2e.sh` was interrupted (Ctrl-C) or `terraform destroy` failed**:
The `EXIT` trap should still have run `terraform destroy`, but to be sure no billable resources are left, run `terraform -chdir=terraform/gke destroy` manually and confirm with `gcloud container clusters list --project "$GCP_PROJECT_ID"`.

**`Day1.cluster.01-gke`/`Decom.cluster.01-gke` fails on `terraform init` with a permissions or 404 error on the GCS bucket**: re-check the `TF_STATE_BUCKET` secret matches `terraform -chdir=terraform/bootstrap output -raw state_bucket`, and that `terraform/bootstrap` finished applying (the bucket and the `roles/storage.objectAdmin` binding for the CI service account must both exist).

**`Decom.cluster.01-gke` (or `Day2.redeploy.02-jenkins`) run manually without a prior `Day1.cluster.01-gke`** (or after the state was already destroyed): `terraform init` will succeed against an empty state, but `terraform output -raw cluster_name` will fail with "no outputs found" — there's nothing to decommission/redeploy in that case.

**WIF auth step fails with `permission denied` / `iam.workloadIdentityPools` not found**: re-run `terraform -chdir=terraform/bootstrap apply` (it may not have finished) and confirm `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_SERVICE_ACCOUNT` match its outputs exactly, and that `github_repo` in `terraform/bootstrap/terraform.tfvars` matches this repo's `org/name`.

## Jenkins & GitOps Push Issues

**GitOps Push Authentication Failure (`exit code 128`) during Jenkins build**:
- **Symptom**: A microservice build fails at the gitops promotion stage when executing `git push origin main` on the `jenkins-2026-gitops-config` repository.
- **Cause**: The `jenkins-credentials` Kubernetes Secret in the `jenkins` namespace was created with empty strings for `git-username` and `git-token`. This typically happens if the GitHub Action provision workflow ran without the `GIT_USERNAME` and `GIT_TOKEN` repository secrets configured.
- **Prevention**: Configure `GIT_USERNAME` and `GIT_TOKEN` as Secrets on your GitHub repository.
- **Hotfix (Manual Resolution)**:
  1. Patch the credentials in the Kubernetes cluster:
     ```bash
     kubectl create secret generic jenkins-credentials \
       --namespace=jenkins \
       --from-literal=git-username="<your-github-username>" \
       --from-literal=git-token="<your-github-token>" \
       --dry-run=client -o yaml | kubectl apply -f -
     ```
  2. Restart the Jenkins pod to reload the JCasC credentials:
     ```bash
     kubectl delete pod jenkins-0 -n jenkins
     ```

**GitOps Sync Token Failure (`ARGOCD_AUTH_TOKEN: parameter not set` / exit code 2)**:
- **Symptom**: The Jenkins build fails at the GitOps Update stage with the error `ARGOCD_AUTH_TOKEN: parameter not set`.
- **Cause**: The `argocd-token` was not generated or was generated after Jenkins already booted, leaving the running Jenkins pod without the `ARGOCD_AUTH_TOKEN` environment variable.
- **Prevention**: The provisioning order is set so that `scripts/08.5-argocd.sh` runs before `scripts/04-jenkins.sh`.
- **Manual Fix**:
  ```bash
  kubectl delete pod jenkins-0 -n jenkins
  ```

---

[← Previous: 901. Local Development](./901-LOCAL_DEVELOPMENT.md) | [🏠 Home](../README.md)

---

*902. Troubleshooting — jenkins-2026*
