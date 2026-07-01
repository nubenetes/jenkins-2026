[← Previous: 901. Local Development](./901-LOCAL_DEVELOPMENT.md) | [🏠 Home](../README.md)

---

# 902. Troubleshooting

## Common Issues

- **`yq` not found**: install [`mikefarah/yq`](https://github.com/mikefarah/yq) (the Go binary — not the Python `yq` wrapper around `jq`).

- **[`scripts/03-observability.sh`](../scripts/03-observability.sh) fails with "Secret ... not found"**: create `observability/otel-collector/secret.yaml` from the `.example` template and `kubectl apply` it (see [901. Quick start](./901-LOCAL_DEVELOPMENT.md)) before re-running.

- **Microservices pods stuck in `ImagePullBackOff`**: expected before any pipeline has run for that service. Check `kubectl -n microservices describe pod <pod>` to confirm it's an image-pull issue, then trigger that service's job in Jenkins.

- **Re-running after a partial failure**: every step is idempotent; just re-run `./scripts/up.sh` (or the individual `scripts/0N-*.sh`). Logs from the last `up.sh`/`down.sh` run are under `logs/`.

- **Rotating the Jenkins admin password**: delete the `jenkins-credentials` Secret in the `jenkins` namespace and re-run [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) + [`scripts/04-jenkins.sh`](../scripts/04-jenkins.sh).

- **Tekton CI dashboard panels show "No data" on a fresh cluster**: expected until a `PipelineRun` has actually run. The run-scoped metrics (`tekton_pipelines_controller_pipelinerun_total` / `_duration_seconds` / `taskrun_total` / `taskruns_pod_latency`) are only created by the controller **after** the first run; before that those panels are empty even though the scrape works (`up{job="tekton-pipelines-controller"}` = 1, `tekton_pipelines_controller_running_pipelineruns` = 0). With Pipelines-as-Code (default when the gateway is enabled), `Day1` sets PaC up but does **not** trigger a build — it waits for a `git push` to the microservices fork. Trigger one (PaC push, the Tekton Dashboard's *Create*, or `kubectl create` a PipelineRun — see [403 § Running a pipeline by hand](./403-TEKTON.md#running-a-pipeline-by-hand-dashboard--kubectl--tkn)) and the panels populate. Same applies to the trace/span-metrics panels (they need a run to emit traces).

## Dataplane V2 enforcement & fresh-cluster stalls

The cluster runs GKE Dataplane V2 (Cilium/eBPF), so NetworkPolicies actually enforce (see [501 § Zero-Trust](./501-PLATFORM_OPERATIONS.md)). A few things look like failures but are expected/self-healing:

- **`microservices-stable` shows ArgoCD health `Unknown` (even when everything works)**: ArgoCD ships **no** built-in health assessment for the CloudNativePG `Cluster`/`Pooler`/`ScheduledBackup` and OpenTelemetry `Instrumentation` CRs the app owns, so the aggregate app health rolled up to `Unknown` (the rollup takes the worst status, and `Unknown` is worst) even though every underlying workload was fine. **Fixed** by custom Lua health checks for those CRDs in [`helm/argocd-values.yaml`](../helm/argocd-values.yaml) (`configs.cm.resource.customizations.health.<group>_<kind>`) — the CNPG `Cluster` reports `Healthy` once its phase is `Cluster in healthy state`, the rest report `Healthy` on reconcile, so the app now goes **Healthy**. To pick the change up on a running cluster: re-run [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) (or `Day1`), then `kubectl annotate application microservices-stable -n argocd argocd.argoproj.io/refresh=hard --overwrite`. Independently, [`scripts/up.sh`](../scripts/up.sh) still gates the pre-OTel-injection wait on the **Deployments becoming Available** (not on app health) — robust even for CRDs without a health check, and waiting on `Healthy` used to burn the full 10-minute timeout. Verify the workloads directly with `kubectl -n microservices get deploy` (gateway + jhipster `Available`).

- **`tekton-pipelines` ArgoCD app `SyncFailed` with `config.webhook.pipeline.tekton.dev` / `tls: unrecognized name` / `x509`**: the Tekton webhook self-issues its serving cert, and on a fresh cluster ArgoCD can first-sync the Tekton config ConfigMaps before that cert exists. This **self-heals**, no manual step: the `tekton-pipelines` app has `syncPolicy.retry` (auto-retry with backoff) so the sync converges once the webhook is up, and it **no longer uses `Replace=true`** — `Replace` used to `kubectl replace` every object on each sync, which re-triggered the webhook and blanked the caBundle (that was also why a **manual** Sync failed even while the app showed Synced/Healthy). If you ever want to force it: `kubectl -n tekton-pipelines rollout restart deploy/tekton-pipelines-webhook`.

- **`gateway` CrashLoop / Liquibase connect-timeout, or pods never Ready**: under enforcement the app needs explicit allows the app chart's own policies miss — egress to CNPG Postgres (by `cnpg.io/cluster`, port 5432) and to the API server (443, for JHipster's Hazelcast discovery). These are carried by the additive `microservices-cnpg-platform` policy in [`infrastructure/networkpolicies.yaml`](../infrastructure/networkpolicies.yaml); confirm it's applied (`kubectl -n microservices get netpol`).

- **A Gateway-exposed UI is unreachable / its GKE backend is `UNHEALTHY`** (argocd, headlamp, …): the NetworkPolicy ingress must allow the **pod** `targetPort` (e.g. argocd-server `8080`, headlamp `4466`), not the Service port — the container-native LB (NEG) sends to the pod port. See the [501 enforcement-gotchas block](./501-PLATFORM_OPERATIONS.md).

- **pgAdmin's "Stable - …" connections time out / won't connect (looks like a wrong password, but isn't)**: the failure is a **TCP connection timeout**, not an auth error — pgAdmin can't reach Postgres at all, so the password from `postgres-*-app` is irrelevant. Root cause is a **NetworkPolicy podSelector mismatch**: `pgadmin-policy` (egress to `microservices:5432` **and** `:443` for the API server) selects `app.kubernetes.io/name: pgadmin4` — the label the pgAdmin chart actually puts on its pods. If it ever reads `pgadmin` (the older value), the policy matches nothing, only the DNS-only `default-deny` applies, and **both** the runtime `5432` egress *and* the `setup-pgpass` init container's `:443` call to the API server are blocked (so there's also no `.pgpass`, breaking zero-password login). Confirm with `kubectl get netpol pgadmin-policy -n pgadmin -o jsonpath='{.spec.podSelector}'` (must be `pgadmin4`) and a TCP test from the pod (`kubectl exec -n pgadmin <pod> -c pgadmin4 -- /venv/bin/python3 -c "import socket; socket.create_connection(('postgres-gateway-rw.microservices.svc',5432),5)"`). The fix lives in [`infrastructure/networkpolicies.yaml`](../infrastructure/networkpolicies.yaml) (applied by `scripts/01-namespaces.sh`, **not** ArgoCD — re-apply with `kubectl apply -f` or re-run `01-namespaces.sh`). Note pgAdmin's PVC is RWO and its Deployment uses `strategy: Recreate`; restart it with `kubectl scale deploy/pgadmin-pgadmin4 -n pgadmin --replicas=0` then `=1` (a `rollout restart` deadlocks on Multi-Attach).

## Switching `observability.mode` on a running cluster

Re-running `Day1` (or [`scripts/03-observability.sh`](../scripts/03-observability.sh)) with a different `observability.mode` converges the **same** cluster onto the new backend; each mode branch retires the other modes' agents so the switch is idempotent. Two things that previously bit on a switch (now handled):

- **`k8s-monitoring` install fails: "A Node Exporter already appears to be running ... host port conflict" (9100)** — switching `oss` → `grafana-cloud`/`managed-*` left the OSS `kube-prometheus-stack` node-exporter DaemonSet (hostPort 9100, via ArgoCD) running while the new mode installed its own. ArgoCD's cascade-prune is async, so it raced the install. `remove_oss_observability_app` now **waits** for that DaemonSet to disappear (with a direct-delete backstop) before the new exporter is installed. If you ever hit it manually: `kubectl delete application observability-oss -n argocd --wait=false; kubectl delete ds -n observability -l app.kubernetes.io/name=prometheus-node-exporter`.

- **Wrong CI-overview dashboard lingers (e.g. "Jenkins CI Overview" on a `ci.engine=tekton` cluster)** — there are four mutually-exclusive CI-overview dashboards, one per engine (`jenkins-overview` · `tekton-overview` · `github-actions-ci` · `argo-workflows-ci`), and only the active engine's is published. Grafana Cloud / Azure Managed Grafana stacks are **persistent**, and `gcx push` / `POST /api/dashboards/db` only upsert, so a previously-published off-engine dashboard survived an engine switch. [`scripts/07-grafana-dashboards.sh`](../scripts/07-grafana-dashboards.sh) now **deletes the three inactive engines' overviews by UID** in every mode (grafana-cloud, managed-azure, managed-aws; oss drops them at render time). To remove a stale one by hand: `curl -X DELETE "$GRAFANA_BASE_URL/api/dashboards/uid/jenkins2026-jenkins-overview" -H "Authorization: Bearer $GRAFANA_API_KEY"`.

## ArgoCD application-controller OOM (Day1 hangs at "Deploy the stack")

**Symptom**: a `Day1` run stalls in [`scripts/up.sh`](../scripts/up.sh) (often when switching
`ci.engine` to a heavy app-of-apps engine — e.g. `jenkins` → `tekton` (or `argoworkflows`) —
**with** `observability.mode=oss`); `kubectl get pods
-n argocd` shows `argocd-application-controller-0` in `CrashLoopBackOff`, and
`kubectl get applications -n argocd` shows `tekton-pipelines` (and others) stuck
with an empty/`OutOfSync` status. The controller's last state is
`reason: OOMKilled, exitCode: 137`.

**Cause**: the application-controller holds the live-state cache of **every**
managed object. The heaviest combination — the OSS stack (kube-prometheus-stack +
Loki + Tempo, hundreds of objects) **and** the full Tekton app-of-apps
(pipelines / triggers / dashboard / chains / pruner / pac + their CRDs) — exceeded
the controller's `1Gi` memory limit. It OOM-loops, can't finish syncing
`tekton-pipelines`, and `up.sh` waits forever.

**Fix**: the controller limit is raised to **3Gi** (request `768Mi`) in
[`helm/argocd-values.yaml`](../helm/argocd-values.yaml); re-run `Day1` (or
[`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh)) to apply. To unblock a **currently hung** run in place:

```bash
kubectl -n argocd patch statefulset argocd-application-controller --type merge \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"application-controller","resources":{"requests":{"memory":"768Mi"},"limits":{"memory":"3Gi"}}}]}}}}'
# the pod recreates with more memory, finishes syncing Tekton, and up.sh proceeds
```

## Decommission stalls (`terraform destroy` hangs for hours on `DELETE_NODE_POOL`)

**Symptom**: a teardown (`Decom.cluster.01`, or the `Decom.infra.00-all` umbrella) runs
for hours and never finishes. `gcloud container operations list --filter='status!=DONE'`
shows a **`DELETE_NODE_POOL` stuck `RUNNING`**; the cluster is `RECONCILING` with its
nodes still alive; `kubectl get pods -A` shows CNPG `postgres-*-N` pods stuck
`Terminating`. There are **no** orphaned load-balancer resources (it is not a network
issue).

**Cause**: GKE node-pool deletion **cordons and drains** each node, which evicts pods
*voluntarily* — and a **PodDisruptionBudget with `ALLOWED DISRUPTIONS: 0`** forbids
that eviction. CNPG creates exactly such PDBs (`postgres-<svc>` / `postgres-<svc>-primary`).
So a Postgres pod can't be evicted, the node can't drain, and `DELETE_NODE_POOL`
waits indefinitely (until the 6 h Actions limit), leaving the cluster — and its
billed nodes — alive.

**Fix (permanent)**: [`scripts/down.sh`](../scripts/down.sh) now **deletes every PodDisruptionBudget up
front** (`kubectl get pdb -A … | delete`), before namespace draining and well before
`terraform destroy`. PDBs only gate *voluntary* disruptions, so removing them is safe
when the whole cluster is being destroyed, and no later drain can be blocked.

**Unblock a teardown that's already hung** (no need to wait for the timeout):

```bash
kubectl delete pdb --all -A   # frees the eviction; the node drains, DELETE_NODE_POOL completes
# then, if the Actions job already died, re-run Decom.cluster.01 so terraform destroy finishes cleanly
```

> **Related decom robustness fixes:** namespace teardown is now **finalize-driven** —
> `down.sh` issues `kubectl delete namespace --wait=false` then force-clears
> `spec.finalizers` via the `/finalize` API, instead of a `--timeout=2m` wait (which
> produced noisy "timed out waiting for the condition" lines and added up to 2 min per
> namespace). The **Gateway-API** deletes deliberately keep a bounded `--timeout`
> *with a real wait* — their finalizers release actual GCP load-balancer resources, so
> force-clearing them would orphan billed infra. Rule of thumb: **force-finalize
> etcd-only objects (namespaces, ArgoCD Apps); wait on finalizers that free external
> cloud resources (Gateway/LB, PVs).**

### Orphaned PersistentVolume disks after a forced teardown

Dynamically-provisioned **PV disks** (`pd.csi.storage.gke.io` — e.g. the CNPG
Postgres volumes) are created by the in-cluster CSI driver, **not** terraform, so
`terraform destroy` cannot delete them. A *clean* teardown reclaims them (the CSI
driver deletes the PD when `down.sh` deletes the PVC); a *forced* teardown (stuck
pods, force-deleted cluster) can leave them behind as small `pd-ssd` disks that keep
billing. They keep the cluster's GKE labels, so `Decom.cluster.01` now **sweeps them
after `terraform destroy`**:

```bash
# what the workflow runs; also handy to clean up by hand after a chaotic teardown
gcloud compute disks list --project "$PROJECT" \
  --filter="labels.goog-k8s-cluster-name=jenkins-2026 AND -users:*" \
  --format="value(name,zone.basename())" \
| while read -r DISK ZONE; do gcloud compute disks delete "$DISK" --zone "$ZONE" --quiet; done
```

### Container-native LB NEGs block the VPC delete (a NEG-delete timeout is normal)

The Gateway uses **container-native load balancing**: each backing Service gets a **NEG**
(Network Endpoint Group). GCP refuses to delete a NEG while a backend service references it,
and a leftover NEG references the VPC subnet — so it **blocks `terraform/gke`'s VPC delete**.
A *timeout deleting a NEG during teardown is expected*, not an error: NEGs are GC'd
**asynchronously** by the GKE controller, so `down.sh` gives it time then forces the rest.
The teardown is **layered** (defense-in-depth — the layers are complementary, not exclusive):

- **L1 — precise GC.** `down.sh` deletes the HTTPRoutes + Gateway with a finalizer-wait
  (`kubectl delete … --timeout`), so the GKE controller releases the whole L7 LB chain
  (forwarding-rule → proxy → url-map → backend-service → NEG) **while the cluster is still
  alive**. The clean path — most NEGs disappear here.
- **L2 — absorb async.** Poll up to **10 min** for the controller's async GC to finish (it
  can lag under load).
- **L3 — dependency-safe backstop.** Force-delete any survivors **in dependency order**: for
  each stuck NEG, delete the forwarding-rules → target-proxies → url-maps → backend-services
  that reference it, *then* the NEG — so the delete never fails with "resource in use"
  (deleting just the NEG would).

**Anti-pattern to avoid:** do **not** destroy the cluster first to "skip" the NEG cleanup —
that kills the controller, orphans the NEGs, and L3 then races leftover backends. The order
(clean up while the cluster is alive → destroy the cluster last) is deliberate. If
`terraform destroy` ever still fails on the VPC with a NEG in use, **re-run `down.sh`**
(idempotent) — by then the controller has usually finished and the NEG drains. Manual one-off:

```bash
gcloud compute network-endpoint-groups list --filter="network:jenkins-2026-vpc"
# find the backend-service pinning a stuck NEG, delete it (--global), then delete the NEG:
gcloud compute backend-services list --format=json \
  | jq -r '.[]|select([.backends[]?.group//""]|any(contains("<neg-name>")))|.name'
gcloud compute network-endpoint-groups delete <neg-name> --zone <zone>
```

## CNPG Postgres WAL backups to GCS fail (`ContinuousArchiving=False`)

**Symptom:** the microservices Postgres works, but the CNPG `Cluster` reports
`ContinuousArchiving=False` and the operator/instance logs show
`barman-cloud-wal-... "Project was not passed and could not be auto-detected"`;
nothing lands in the `*-jenkins-2026-postgres-backups` GCS bucket. App health is
unaffected (postgres still serves on 5432).

**Cause:** the GitOps chart's `templates/postgres.yaml` reads
`global.gcpProject` / `global.gcpServiceAccount` / `global.gcsBackupBucket`, but
`values-stable.yaml` left them unset, so it rendered the **placeholder defaults**
(`jenkins-2026-sa@jenkins-2026` for the `serviceAccountTemplate` Workload-Identity
annotation, `gs://jenkins-2026-postgres-backups` for `destinationPath`). The KSA
was therefore annotated with a **GSA in a non-existent project** → the postgres
pods got no GCP identity → barman couldn't authenticate or detect the project.

**Fix (infra-side; the GitOps repo is untouched — the AppSet helm params override
the chart placeholders at deploy):**
1. `terraform/gke` creates a least-privilege GSA `jenkins-2026-pg-backups`
   (`roles/storage.objectAdmin` on the backups bucket) + Workload-Identity bindings
   for each CNPG Cluster KSA (`microservices/postgres-gateway`,
   `microservices/postgres-jhipstersamplemicroservice`) — same pattern as the ESO GSA.
2. [`argocd/microservices-appset.yaml`](../argocd/microservices-appset.yaml) passes `global.gcpProject` /
   `gcpServiceAccount` / `gcsBackupBucket` as helm parameters, substituted from the
   real project in [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh).
3. [`infrastructure/networkpolicies.yaml`](../infrastructure/networkpolicies.yaml) allows the `microservices` namespace egress
   to the node-local metadata server (`169.254.169.254:80/988`) so the pods can fetch
   the WI token under the namespace default-deny.

Apply with a **Day1 re-run** (Terraform creates the GSA + bindings; ArgoCD re-renders
the AppSet). Verify: `kubectl get cluster -n microservices` shows
`ContinuousArchiving=True` and objects appear under `gs://<project>-jenkins-2026-postgres-backups/<svc>/`.

## ArgoCD OIDC Issues

**ArgoCD OIDC Login fails with `redirect_uri_mismatch` or `Invalid redirect URL`**:
- Ensure the GKE cluster was provisioned with `enable_gateway: true` in GitHub Actions. If the gateway is disabled, redirect URLs in `argocd-cm` will fallback to localhost or empty domains, breaking OIDC.
- Verify that `https://argocd.<baseDomain>/api/dex/callback` is added to your Google OAuth client in the GCP Console.
- If you terminate TLS at the gateway and route traffic over HTTP to the backend `argocd-server`, ensure that the `url` field in `argocd-cm` is set to `https://...` (without trailing slash) and the server runs in `--insecure` mode so it trusts the `X-Forwarded-Proto: https` header sent by Google Cloud Load Balancer.

**ArgoCD installation stuck in `pending-install`**: The [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) script includes recovery logic to detect and clear stuck Helm releases. If it hangs, the script will automatically attempt to `helm uninstall` and retry.

**Gateway resource mapping errors (`GCPBackendPolicy` / `HealthCheckPolicy`)**: Ensure you are using `networking.gke.io/v1` as the API version in [`scripts/09-gateway.sh`](../scripts/09-gateway.sh) (already fixed in `main`/`develop`).

## Terraform & CI Issues

**[`test/e2e.sh`](../test/e2e.sh) was interrupted (Ctrl-C) or `terraform destroy` failed**:
The `EXIT` trap should still have run `terraform destroy`, but to be sure no billable resources are left, run `terraform -chdir=terraform/gke destroy` manually and confirm with `gcloud container clusters list --project "$GCP_PROJECT_ID"`.

**`Day1.cluster.01-gke`/`Decom.cluster.01-gke` fails on `terraform init` with a permissions or 404 error on the GCS bucket**: re-check the `TF_STATE_BUCKET` secret matches `terraform -chdir=terraform/bootstrap output -raw state_bucket`, and that `terraform/bootstrap` finished applying (the bucket and the `roles/storage.objectAdmin` binding for the CI service account must both exist).

**`Decom.cluster.01-gke` (or `Day2.redeploy.02-jenkins`) run manually without a prior `Day1.cluster.01-gke`** (or after the state was already destroyed): `terraform init` will succeed against an empty state, but `terraform output -raw cluster_name` will fail with "no outputs found" — there's nothing to decommission/redeploy in that case.

**WIF auth step fails with `permission denied` / `iam.workloadIdentityPools` not found**: re-run `terraform -chdir=terraform/bootstrap apply` (it may not have finished) and confirm `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_SERVICE_ACCOUNT` match its outputs exactly, and that `github_repo` in `terraform/bootstrap/terraform.tfvars` matches this repo's `org/name`.

**`Decom.infra.01 Gateway` fails on `terraform destroy` with `Error 403: Permission 'certificatemanager.certmapentries.delete' denied`**: the CI service account had `roles/certificatemanager.editor`, which — surprisingly — grants create/get/list/update but **no `.delete`** on *any* certificatemanager resource (certs/certmaps/certmapentries/dnsauthorizations). So the Gateway bootstrap could create the cert map but not tear it down. Fixed in `terraform/bootstrap` by switching to **`roles/certificatemanager.owner`** (includes the deletes). **This is a one-time, human-run bootstrap change** — re-run `terraform -chdir=terraform/bootstrap apply` to grant it, then re-run `Decom.infra.01` to finish removing the cert map/entry/cert/DNS-authorization (a failed destroy deletes the static IP first, leaving those behind in state + GCP).

## Jenkins & GitOps Push Issues

**Microservices pipeline targets namespace `"null"` (k6 hits `gateway.null.svc`, deploy fails `namespace "null"`)**:
- **Symptom**: the *Integration k6 Smoke Test* stage fails — k6 logs `lookup gateway.null.svc.cluster.local … no such host`, 100% requests fail, `http_req_failed` threshold crossed; and/or the *Deploy* stage logs `... is forbidden ... in the namespace "null"`. The seed-baked job config has the **correct** `targetNamespace: 'microservices'`, so it looks impossible.
- **Cause**: `MicroservicesPipeline` named its argument map **`params`** but declares **no `parameters{}` block**, so inside the declarative pipeline `params.targetNamespace` resolves to the *empty build-parameters global* (not the seed-baked arg) → the string `"null"`. It surfaces on the **first build after a (re)seed** (Jenkins doesn't apply a job's default param values on that first build).
- **Fix (already in the shared library)**: the arg is renamed to **`cfg`** (the pattern every other `vars/*.groovy` uses — `cfg` is unambiguously the method arg); the k6 job is triggered with `TARGET_NAMESPACE`/`ENV_NAME` passed **explicitly** (not relying on defaults); and the k6 pipeline coalesces `preset → param → cfg → default`. Jenkins loads the shared library from the deployed branch, so just **re-run the job** to pick it up. (A companion Groovy fix: the k6 summary printer crashed via `String.format('%.2f', <Integer>)` when a rate was exactly `0`/`1` — `numOf()` now returns a `double`.)

**Seed job times out fetching the CSRF crumb (HTTP 401) right after switching to `secrets.backend=eso`**:
- **Symptom**: `06-seed-pipelines.sh` logs `Timed out (5m) waiting for the Jenkins crumbIssuer API` / `seed-jobs attempt N failed`, even though `jenkins-0` is `2/2 Running`. A `curl -u admin:<pw>` against `/crumbIssuer/api/json` returns **401**.
- **Cause**: switching an **existing** cluster to `eso` (or the first `imperative→eso` migration) seeds a **new** stable `admin-password` into `jenkins-credentials` (via `sm_keep_or_generate` → Secret Manager → ESO `Merge`), but the **already-running** Jenkins pod was configured by JCasC with the *old* password and didn't adopt the new one. The seed job authenticates with the Secret's (new) password → 401. The ESO side is fine (`ExternalSecret jenkins-credentials` is `SecretSynced`, the Secret has all keys).
- **Fix**: restart Jenkins so JCasC re-applies `securityRealm` with the current Secret value — **`kubectl delete pod jenkins-0 -n jenkins`** (a `kubectl rollout restart` is reverted by ArgoCD's selfHeal, which manages the StatefulSet; deleting the pod is recreated cleanly). Verify: `PW=$(kubectl get secret jenkins-credentials -n jenkins -o jsonpath='{.data.admin-password}'|base64 -d); kubectl exec -n jenkins jenkins-0 -c jenkins -- curl -s -o /dev/null -w '%{http_code}' -u admin:"$PW" http://localhost:8080/crumbIssuer/api/json` → **200**, then relaunch Day1. This is a **one-time** event per cluster — the password is stable thereafter (see [201](./201-ARCHITECTURE.md) § Feature-flag convergence).

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
- **Prevention**: The provisioning order is set so that [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) runs before [`scripts/04-jenkins.sh`](../scripts/04-jenkins.sh).
- **Manual Fix**:
  ```bash
  kubectl delete pod jenkins-0 -n jenkins
  ```

## Angular build fails after adding Grafana Faro (`TS2304` / `TS2307`)

**Symptom.** `gateway-develop` (any build of the Faro-instrumented gateway) fails in `npm run webapp:build` (frontend-maven-plugin):

```
error TS2304: Cannot find name 'global'.     (@grafana/faro-core)
error TS2307: Cannot find module 'path'.     (@opentelemetry/instrumentation, via @grafana/faro-web-tracing)
```

**Cause.** The Faro Web SDK + Web Tracing pull transitive `.d.ts` definitions that reference **Node.js** globals/modules (`global`, `path`), but the gateway's Angular `tsconfig.json` ships `types: []` and no `skipLibCheck`, so TypeScript type-checks those library `.d.ts` and fails — they are browser-safe at *runtime*; only the type refs are Node-y.

**Fix.** Add `"skipLibCheck": true` to the gateway `tsconfig.json` `compilerOptions` (it only skips type-checking `node_modules` `.d.ts`, not your code). Applied on the gateway **develop** branch alongside the Faro instrumentation.

---

[← Previous: 901. Local Development](./901-LOCAL_DEVELOPMENT.md) | [🏠 Home](../README.md)

---

*902. Troubleshooting — jenkins-2026*
