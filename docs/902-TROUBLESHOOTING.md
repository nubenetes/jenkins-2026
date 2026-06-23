[← Previous: 901. Local Development](./901-LOCAL_DEVELOPMENT.md) | [🏠 Home](../README.md)

---

# 902. Troubleshooting

## Common Issues

- **`yq` not found**: install [`mikefarah/yq`](https://github.com/mikefarah/yq) (the Go binary — not the Python `yq` wrapper around `jq`).

- **`scripts/03-observability.sh` fails with "Secret ... not found"**: create `observability/otel-collector/secret.yaml` from the `.example` template and `kubectl apply` it (see [901. Quick start](./901-LOCAL_DEVELOPMENT.md)) before re-running.

- **Microservices pods stuck in `ImagePullBackOff`**: expected before any pipeline has run for that service. Check `kubectl -n microservices describe pod <pod>` to confirm it's an image-pull issue, then trigger that service's job in Jenkins.

- **Re-running after a partial failure**: every step is idempotent; just re-run `./scripts/up.sh` (or the individual `scripts/0N-*.sh`). Logs from the last `up.sh`/`down.sh` run are under `logs/`.

- **Rotating the Jenkins admin password**: delete the `jenkins-credentials` Secret in the `jenkins` namespace and re-run `scripts/01-namespaces.sh` + `scripts/04-jenkins.sh`.

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
