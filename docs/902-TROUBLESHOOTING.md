[← Previous: 901. Local Development](./901-LOCAL_DEVELOPMENT.md) | [🏠 Home](../README.md) | [→ Next: 903. Glossary](./903-GLOSSARY.md)

---

# 902. Troubleshooting

## Common Issues

- **`yq` not found**: install [`mikefarah/yq`](https://github.com/mikefarah/yq) (the Go binary — not the Python `yq` wrapper around `jq`).

- **[`scripts/03-observability.sh`](../scripts/03-observability.sh) fails with "Secret ... not found"**: create `observability/otel-collector/secret.yaml` from the `.example` template and `kubectl apply` it (see [901. Quick start](./901-LOCAL_DEVELOPMENT.md)) before re-running.

- **Microservices pods stuck in `ImagePullBackOff`**: expected before any pipeline has run for that service. Check `kubectl -n microservices describe pod <pod>` to confirm it's an image-pull issue, then trigger that service's job in Jenkins.

- **Re-running after a partial failure**: every step is idempotent; just re-run `./scripts/up.sh` (or the individual `scripts/0N-*.sh`). The parallel helm-uninstall steps of the last `down.sh` run log to `logs/<release>.log` (`run_bg` in [`scripts/lib/common.sh`](../scripts/lib/common.sh)); `up.sh` prints to stdout only.

- **Rotating the Jenkins admin password** (`secrets.backend=imperative`): delete the `jenkins-credentials` Secret in the `jenkins` namespace and re-run [`scripts/01-namespaces.sh`](../scripts/01-namespaces.sh) + [`scripts/04-jenkins.sh`](../scripts/04-jenkins.sh). With `secrets.backend=eso` that recipe restores the **old** password (`sm_keep_or_generate` keeps the existing Secret Manager value and ESO re-syncs it) — delete the **Secret Manager** secret first (`gcloud secrets delete jenkins-credentials`), then re-run the two scripts and `kubectl delete pod jenkins-0 -n jenkins`.

- **Tekton CI dashboard panels show "No data" on a fresh cluster**: expected until a `PipelineRun` has actually run. The run-scoped metrics (`tekton_pipelines_controller_pipelinerun_total` / `_duration_seconds` / `taskrun_total` / `taskruns_pod_latency`) are only created by the controller **after** the first run; before that those panels are empty even though the scrape works (`up{job="tekton-pipelines-controller"}` = 1, `tekton_pipelines_controller_running_pipelineruns` = 0). With the default `tekton.seedRuns: true`, `Day1` ([`06-tekton-pipelines.sh`](../scripts/06-tekton-pipelines.sh)) seeds one PipelineRun per service from `tekton/runs/`, so these panels populate once the seeded runs finish. With `tekton.seedRuns=false` (`JENKINS2026_TEKTON_SEED_RUNS`), PaC is set up but no build is triggered — it waits for a `git push` to the microservices fork; trigger one by hand (the Tekton Dashboard's *Create*, or `kubectl create` a PipelineRun — see [403 § Running a pipeline by hand](./403-TEKTON.md#running-a-pipeline-by-hand-dashboard--kubectl--tkn)) and the panels populate. Same applies to the trace/span-metrics panels (they need a run to emit traces).

## Dataplane V2 enforcement & fresh-cluster stalls

The cluster runs GKE Dataplane V2 (Cilium/eBPF), so NetworkPolicies actually enforce (see [501 § Zero-Trust](./501-PLATFORM_OPERATIONS.md)). A few things look like failures but are expected/self-healing:

- **`microservices-stable` shows ArgoCD health `Unknown` (even when everything works)**: ArgoCD ships **no** built-in health assessment for the CloudNativePG `Cluster`/`Pooler`/`ScheduledBackup` and OpenTelemetry `Instrumentation` CRs the app owns, so the aggregate app health rolled up to `Unknown` (the rollup takes the worst status, and `Unknown` is worst) even though every underlying workload was fine. **Fixed** by custom Lua health checks for those CRDs in [`helm/argocd-values.yaml`](../helm/argocd-values.yaml) (`configs.cm.resource.customizations.health.<group>_<kind>`) — the CNPG `Cluster` reports `Healthy` once its `Ready` condition is `True` (ArgoCD's Lua sandbox doesn't load the `string` library, so the check deliberately keys on the Ready condition instead of string-matching the phase), the rest report `Healthy` on reconcile, so the app now goes **Healthy**. To pick the change up on a running cluster: re-run [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) (or `Day1`), then `kubectl annotate application microservices-stable -n argocd argocd.argoproj.io/refresh=hard --overwrite`. Independently, [`scripts/up.sh`](../scripts/up.sh) still gates the pre-OTel-injection wait on the **Deployments becoming Available** (not on app health) — robust even for CRDs without a health check, and waiting on `Healthy` used to burn the full 10-minute timeout. Verify the workloads directly with `kubectl -n microservices get deploy` (gateway + jhipster `Available`).

- **`tekton-pipelines` ArgoCD app `SyncFailed` with `config.webhook.pipeline.tekton.dev` / `tls: unrecognized name` / `x509`**: the Tekton webhook self-issues its serving cert, and on a fresh cluster ArgoCD can first-sync the Tekton config ConfigMaps before that cert exists. This **self-heals**, no manual step: the `tekton-pipelines` app has `syncPolicy.retry` (auto-retry with backoff) so the sync converges once the webhook is up, and it **no longer uses `Replace=true`** — `Replace` used to `kubectl replace` every object on each sync, which re-triggered the webhook and blanked the caBundle (that was also why a **manual** Sync failed even while the app showed Synced/Healthy). If you ever want to force it: `kubectl -n tekton-pipelines rollout restart deploy/tekton-pipelines-webhook`.

- **`gateway` CrashLoop / Liquibase connect-timeout, or pods never Ready**: under enforcement the app needs explicit allows the app chart's own policies miss — egress to CNPG Postgres (by `cnpg.io/cluster`, port 5432) and to the API server (443, for JHipster's Hazelcast discovery). These are carried by the additive `microservices-cnpg-platform` policy in [`infrastructure/networkpolicies.yaml`](../infrastructure/networkpolicies.yaml); confirm it's applied (`kubectl -n microservices get netpol`).

- **A Gateway-exposed UI is unreachable / its GKE backend is `UNHEALTHY`** (argocd, headlamp, …): the NetworkPolicy ingress must allow the **pod** `targetPort` (e.g. argocd-server `8080`, headlamp `4466`), not the Service port — the container-native LB (NEG) sends to the pod port. See the [501 enforcement-gotchas block](./501-PLATFORM_OPERATIONS.md).

- **pgAdmin's "Stable - …" connections time out / won't connect (looks like a wrong password, but isn't)**:
  - **Symptom**: a **TCP connection timeout**, not an auth error — pgAdmin can't reach Postgres at all, so the password from `postgres-*-app` is irrelevant.
  - **Cause**: a **NetworkPolicy podSelector mismatch**. `pgadmin-policy` (egress to `microservices:5432` **and** `:443` for the API server) selects `app.kubernetes.io/name: pgadmin4` — the label the pgAdmin chart actually puts on its pods. If it ever reads `pgadmin` (the older value), the policy matches nothing, only the DNS-only `default-deny` applies, and **both** the runtime `5432` egress *and* the `setup-pgpass` init container's `:443` call to the API server are blocked (so there's also no `.pgpass`, breaking zero-password login).
  - **Confirm**: `kubectl get netpol pgadmin-policy -n pgadmin -o jsonpath='{.spec.podSelector}'` (must be `pgadmin4`), and a TCP test from the pod: `kubectl exec -n pgadmin <pod> -c pgadmin4 -- /venv/bin/python3 -c "import socket; socket.create_connection(('postgres-gateway-rw.microservices.svc',5432),5)"`.
  - **Fix**: [`infrastructure/networkpolicies.yaml`](../infrastructure/networkpolicies.yaml) (applied by `scripts/01-namespaces.sh`, **not** ArgoCD) — re-apply with `kubectl apply -f` or re-run `01-namespaces.sh`.
  - **Restart gotcha**: pgAdmin's PVC is RWO and its Deployment uses `strategy: Recreate`; restart with `kubectl scale deploy/pgadmin-pgadmin4 -n pgadmin --replicas=0` then `=1` (a `rollout restart` deadlocks on Multi-Attach).

## Switching `observability.mode` on a running cluster

Re-running `Day1` (or [`scripts/03-observability.sh`](../scripts/03-observability.sh)) with a different `observability.mode` converges the **same** cluster onto the new backend; each mode branch retires the other modes' agents so the switch is idempotent. Two things that previously bit on a switch (now handled):

- **`k8s-monitoring` install fails: "A Node Exporter already appears to be running ... host port conflict" (9100)** — switching `oss` → `grafana-cloud`/`managed-*` left the OSS `kube-prometheus-stack` node-exporter DaemonSet (hostPort 9100, via ArgoCD) running while the new mode installed its own. ArgoCD's cascade-prune is async, so it raced the install. `remove_oss_observability_app` now **waits** for that DaemonSet to disappear (with a direct-delete backstop) before the new exporter is installed. If you ever hit it manually: `kubectl delete application observability-oss -n argocd --wait=false; kubectl delete ds -n observability -l app.kubernetes.io/instance=oss-kube-prometheus-stack,app.kubernetes.io/name=prometheus-node-exporter` (scope by the **instance** label — the bare name label also matches the managed-azure/aws modes' own standalone node-exporter and would delete it).

- **Wrong CI-overview dashboard lingers (e.g. "Jenkins CI Overview" on a `ci.engine=tekton` cluster)** — there are four mutually-exclusive CI-overview dashboards, one per engine (`jenkins-overview` · `tekton-overview` · `github-actions-ci` · `argo-workflows-ci`), and only the active engine's is published. Grafana Cloud / Azure Managed Grafana stacks are **persistent**, and `gcx push` / `POST /api/dashboards/db` only upsert, so a previously-published off-engine dashboard survived an engine switch. [`scripts/07-grafana-dashboards.sh`](../scripts/07-grafana-dashboards.sh) now **deletes the three inactive engines' overviews by UID** in every mode (grafana-cloud, managed-azure, managed-aws; oss drops them at render time). The uid is derived from each canonical JSON — it is *not* always `jenkins2026-<name>` (`jenkins-overview` carries a Grafana-generated uid). To remove a stale one by hand: `curl -X DELETE "$GRAFANA_BASE_URL/api/dashboards/uid/$(jq -r .uid observability/grafana/dashboards/jenkins-overview.json)" -H "Authorization: Bearer $GRAFANA_API_KEY"`.

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

> **The sweep also catches *prior-run* orphans (#545).** It used to gate on `CLUSTER_NAME`
> from **this** run's `terraform output` — so disks left by an **earlier** teardown (whose
> cluster is already out of state → empty output) were never swept, orphaning them
> indefinitely (found live: **31 disks / ~58 GB** billing after a rebuild). The step now runs
> `if: always()` and falls back to the `terraform/gke` `var.cluster_name` default
> (`jenkins-2026`) when the output is empty. To purge a project **by hand** right now, run the
> command above (it's label-scoped and safe — the disks are detached once the cluster is gone).

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

> To **restore data** from these backups (not just fix archiving), see [Runbook: CNPG Restore from Backup](./runbooks/cnpg-restore-from-backup.md).

## CNPG WAL archiving fails after a rebuild (`Expected empty archive`)

**Symptom:** after a **Decom + Day1 rebuild** (not the first-ever provision), the
CNPG `Cluster` reports `ContinuousArchiving=False`, `Backup` objects sit in phase
`walArchivingFailing`, `cnpg_collector_last_available_backup_timestamp` stays `0`
(the Postgres dashboard's *Time since last successful backup* reads
**"no backups configured"** even though `barmanObjectStore` *is* set), and the
instance logs show `barman-cloud-check-wal-archive … ERROR: WAL archive check
failed for server <cluster>: **Expected empty archive**`. Postgres itself is
healthy. *(Distinct from the auth-side `ContinuousArchiving=False` above.)*

**Cause:** every Day1 bootstraps the clusters via **fresh `initdb`** (a new
PostgreSQL system id) into a **fixed** barman path (`gs://<bucket>/<service>`,
`serverName` defaults to the cluster name), but the backups bucket is **persistent**
(created by `terraform/bootstrap`, survives Decom). A prior incarnation's WALs are
still in that path, so CNPG's `barman-cloud-check-wal-archive` — a safety check
that refuses to mix two clusters' WAL streams — fails with *Expected empty archive*
and archiving/backups never start. First-ever provision works (empty path); the
break appears only after the **first rebuild**.

**Fix:** [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) clears the stale
archive on a **fresh provision only** — guarded so it runs before the
ApplicationSet creates the clusters and *only when no live CNPG `Cluster` exists*,
so a re-run against a running cluster never touches its backups. Applied by any
**Day1**. For an **already-broken running cluster**, empty the path by hand
(the CI SA has `roles/storage.admin` on the bucket):

```bash
# destroys the orphaned WALs of the PRIOR incarnation (useless for the current
# cluster — different system id); archiving recovers on CNPG's next ~30s retry.
gsutil -m rm -r "gs://<project>-jenkins-2026-postgres-backups/<service>/**"
kubectl cnpg backup <cluster> -n microservices   # optional: first recoverability point now
```

Verify: `kubectl get cluster -n microservices` → `ContinuousArchiving=True`, and
*Time since last successful backup* shows a real value once a backup completes.

> The same `Expected empty archive` check can bite during a **restore** if you recover into a non-empty archive prefix — see [Runbook: CNPG Restore from Backup § 6b](./runbooks/cnpg-restore-from-backup.md#6b-the-servername--system-id-gotcha-expected-empty-archive).

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

## `Day2.traffic.01-k6` "VIEW IN GRAFANA" link is dead (Cloudflare `Error 1016`)

**Symptom:** the k6 traffic workflow's summary prints a Grafana Cloud URL
(`https://jenkins2026obs<slug>.grafana.net/...`) that fails with **Cloudflare
`Error 1016 — Origin DNS error`**, even though the cluster runs
`observability.mode=oss` (its Grafana is the in-cluster `grafana.<baseDomain>`).

**Cause:** the workflow **auto-detects the active obs mode from in-cluster
credential-Secret presence** (`aws-managed-credentials` → `azure-monitor-credentials`
→ `grafana-cloud-credentials` → else `oss`). A **stale `grafana-cloud-credentials`
Secret** left in the `observability` namespace by an earlier `grafana-cloud`
provisioning (before switching to `oss`) makes detection pick `grafana-cloud` and
read the **destroyed** stack's URL from it → the dead link. A mode-switch
**residue** issue (see [104](104-REBUILD_SAFETY.md)).

**Fix** (PR #492): [`scripts/03-observability.sh`](../scripts/03-observability.sh)
now deletes the OTHER modes' credential Secrets before provisioning the active one,
enforcing the single-active-mode invariant. To unstick a **live** cluster now:

```bash
# delete whichever inactive-mode credential Secret is stale (here: grafana-cloud on an oss cluster)
kubectl delete secret grafana-cloud-credentials -n observability --ignore-not-found
# a Day1 re-run reconciles this automatically; the next k6 run then detects oss -> grafana.<baseDomain>
```

## RUM dashboard "Sessions" / "Sessions over time" panels show "No data" after repeated k6 RUM testing

**Symptom:** the "CI-CD Frontend RUM (Angular / Faro)" dashboard's **Sessions**
(stat) and **Sessions over time** (timeseries) panels show **No data**, even
though other RUM panels (Web Vitals, page views, errors) are populated and
`observability.mode=oss` Loki genuinely holds the Faro session logs.

**Cause:** both panels count distinct sessions with the LogQL idiom
`count(count by (session_id)(count_over_time({service_name="$app",
deployment_environment="$deployment_environment"} | logfmt | session_id!=""
[range])))`. After a `| logfmt` parser stage, **every extracted field** (not just
`session_id` — also `page_url`, `browser_name`, per-request timestamps, Web
Vitals values, …) becomes part of each log line's label set for the purposes of
the range-vector aggregation, so `count_over_time(...)` materialises **one
query-time series per log line**, not one per distinct session. Loki's default
`limits_config.max_query_series` is **500**; repeated synthetic RUM runs
(`Day2.traffic.01-k6` `rum-faro` preset, `Day2.traffic.02-rum`) accumulate far
more than 500 distinct sessions within a few hours, so the query errors with
*"maximum number of series (500) reached for a single query"* — which Grafana
renders as **No data** instead of surfacing the underlying error. Confirmed live:
730 distinct `session_id` values existed within a 6h window for a single
environment.

**Fix:** [`observability/grafana/values-oss-loki.yaml`](../observability/grafana/values-oss-loki.yaml)
now sets `loki.limits_config.max_query_series: 10000`, giving the dashboard's
session-counting queries headroom appropriate for demo/PoC-scale repeated RUM
testing. Apply with a **Day1 re-run** or an ArgoCD hard-refresh of the `oss-loki`
Application; the fix is config-only (no schema/data migration, single-binary
Loki restarts with the new limit).

## `Day2.scale.01 Pause` hangs on the node-pool resize (CNPG PDB blocks it)

**Symptom:** the Pause workflow disables autoscaling/autoRepair/autoUpgrade and
force-drains fine, but the final `gcloud container clusters resize --num-nodes 0`
step runs for ~15 min and then **fails with exit 1** (`Operation ... is still
running`), while server-side the `SET_NODE_POOL_SIZE` operation stays `RUNNING`
far longer, the MIG `targetSize` never drops, and `kubectl get pods -o wide`
shows CNPG Postgres pods still `Running` on a node that was **not** in the
original node list. (The `gcloud` client gives up at its own ~15 min timeout; the
GKE operation itself keeps going — GKE's resize drain honours PDBs for up to ~1h
before forcing through, so it is a long stall, not a true infinite hang.)

**Cause:** the resize's OWN internal node drain (unlike the workflow's earlier
`--disable-eviction` force-drain) **respects PodDisruptionBudgets**. CNPG creates
`postgres-*` / `postgres-*-primary` PDBs with `ALLOWED DISRUPTIONS: 0`. The
workflow force-drained a one-shot `kubectl get nodes` snapshot, but a node can
appear **after** that snapshot — e.g. an auto-repair already in flight when the
workflow disabled autoRepair is **not cancelled** ([GKE docs](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/node-auto-repair))
and completes on its own, re-creating a node onto which CNPG pods reschedule. That
node was never force-drained, so the resize's PDB-respecting drain stalls on it.
This is the exact bug `scripts/down.sh` already fixed for Decom (a stuck CNPG pod
kept a `DELETE_NODE_POOL` op `RUNNING` for hours, run 28202019543).

**Fix:** `Day2.scale.01-pause.yml` now **deletes every PodDisruptionBudget up
front** (right after `get-credentials`), mirroring `scripts/down.sh` — with no
0-disruption PDB to honour, the resize's internal drain can never stall, no matter
when or why a node appears. Safe: PDBs gate only *voluntary* disruptions (pods and
their PVs are untouched), and CNPG recreates them on `Day2.scale.02 Resume`.
To unstick a **live** run already hanging: `kubectl delete pdb -A --all` — the
in-flight `SET_NODE_POOL_SIZE` operation then completes on its own within a minute.

## Managed-mode collector shows "No data" on infra panels (Container CPU)

**Symptom:** on `observability.mode=managed-azure` (or `managed-aws`), the Kubernetes
infra panels — **Container CPU (cores)** and any other cAdvisor / kube-state panel —
show **"No data"** in Azure Managed Grafana / Amazon Managed Grafana, while the app and
CNPG panels are fine. Nothing is shown as an error on the dashboard.

**Cause:** unlike `oss`/`grafana-cloud` (where kube-prometheus-stack / Grafana Alloy
scrape the infra in a **separate** component), the **managed-mode gateway collector
scrapes all the in-cluster infra itself** (cAdvisor + kubelet + kube-state + node-exporter,
via its `prometheus` receiver) and remote-writes it to the managed Prometheus. cAdvisor is
high-cardinality; if the collector's memory limit is too low it sits above the
`memory_limiter` soft limit (`limit_percentage: 80`) and the processor **refuses** the
scraped data **before** it reaches the exporter — a **silent** drop (no export error,
nothing arrives at the backend). The signature is only in the collector logs:

```bash
kubectl logs -n observability deploy/otel-collector-gateway | grep "data refused"
# error  Scrape commit failed  ... "scrape_pool": "cadvisor"  "err": "data refused due to high memory usage"
```

Not RBAC (the `nodes/proxy` rule is present) and not a metric-name issue.

**Fix:** size the gateway collector to *what it scrapes* — **1Gi** when it self-scrapes
cAdvisor/kube-state (managed-azure/aws), **512Mi** otherwise (oss/grafana-cloud, which
delegate infra scraping). `managed-aws` already carried this; `managed-azure` was raised to
match in [`values-managed-azure.yaml`](../observability/otel-collector/values-managed-azure.yaml).
Do **not** bump oss/grafana-cloud — their collector doesn't scrape cAdvisor, so 512Mi is
right-sized (full rationale + matrix in
[301 § Per-mode metrics collection & collector sizing](301-OBSERVABILITY.md#per-mode-metrics-collection--collector-sizing)).
Apply durably with a **Day1 re-run** (helm upgrade); unstick a **live** collector now:

```bash
kubectl -n observability set resources deploy/otel-collector-gateway \
  --limits=memory=1Gi --requests=memory=512Mi   # restarts the pod; cAdvisor flows in ~2 min
```

Because the drop is silent, an **alert** on `otelcol_processor_refused_metric_points` is
the durable systemic guard (see the sizing note in 301).

## GCP Secret Manager secrets remain after a Decom (`secrets.backend=eso`)

**Symptom:** you ran a `Decom` (even the `Decom.infra.00 Everything` umbrella) and the
cluster/backends are gone, but the GCP **Secret Manager** page for the project still lists
secrets — `jenkins-credentials`, `tekton-*`, `argoworkflows-*`, `arc-*`, `ghcr-credentials`,
`headlamp-credentials`, `k6-cloud`, `pac-webhook`, … (often the **union of every CI engine**
you ran, since engine switches don't sweep them either).

**Cause — mostly by design, plus one gap.** In `eso` mode, GCP Secret Manager is the
**persistent source of truth**, deliberately **outside the cluster lifecycle** (ESO syncs it
*into* the cluster). A Decom tears down the *cluster*; the in-cluster `ExternalSecret`/Secrets
die with the namespaces, but the **upstream Secret Manager entries persist**. This is partly
intentional — `sm_keep_or_generate` ([`lib/secrets.sh`](../scripts/lib/secrets.sh)) relies on
generated secrets (e.g. the **Jenkins admin password**) surviving a cluster Decom so they stay
**stable across rebuilds**. Historically [`down.sh`](../scripts/down.sh) deleted **only** the
`gateway-iap-oauth` secret (cheaply re-derived from a GitHub secret); everything else was left.
(The persistent **bootstrap** tier — WIF, state bucket, DNS zone, backups bucket — likewise
survives on purpose; only [`scripts/bootstrap.sh`](../scripts/bootstrap.sh) `down` removes it.)

**Fix / how to purge them (#544).** `provision_secret` now **labels** every pushed secret
`managed-by=jenkins-2026`, and `down.sh` has an **opt-in** full sweep:

- **`Decom.infra.00 Everything`** now defaults its **`purge_secrets` checkbox ON** — a full
  teardown deletes them all. Untick it to keep them.
- **`Decom.cluster.01-gke`** keeps `purge_secrets` **OFF** (a plain cluster teardown preserves
  the stable-password secrets for a rebuild); tick it for a full clean.
- Locally: `J2026_PURGE_SECRETS=true ./scripts/down.sh`.

To clean a project **by hand** right now (label-scoped, safe — touches only our secrets;
purged secrets are re-pushed/regenerated on the next Day1):

```bash
gcloud secrets list --project "$PROJECT" --filter="labels.managed-by=jenkins-2026" \
  --format="value(name.basename())" \
| while read -r S; do gcloud secrets delete "$S" --project "$PROJECT" --quiet; done
```

(Secrets created *before* this labelling won't carry the label — a Day1 re-run re-labels them,
or delete those by name.)

## GitHub Actions (ARC) CI run hangs on a vanished runner (node DiskPressure eviction)

**Symptom:** on `ci.engine=githubactions`, a fork's CI run (e.g. the gateway
`microservices-ci.yml`) sits **`in_progress` forever** on GitHub even though every
real step — build, Trivy scan, GHCR push, GitOps tag bump, ArgoCD sync, smoke —
already **succeeded** in the logs; you **can't cancel** it (`Cannot cancel a
workflow run that is completed`). In the cluster the runner pod is **gone**:

```bash
# from Windows without the auth plugin — see the kubectl-cluster-access memory
kubectl -n arc-runners get pods                     # the run's runner pod is absent
kubectl -n arc-runners get pod <runner> -o jsonpath='{.status.reason} {.status.message}'
#   Evicted  The node was low on resource: ephemeral-storage. ...
kubectl get node <node> -o jsonpath='{range .status.conditions[?(@.type=="DiskPressure")]}{.status}{end}'
#   True
```

**Cause:** the ephemeral ARC runner pods run on the **50 GB `ci-spot` nodes**
(`terraform/gke` `var.disk_size_gb`, kept small for `SSD_TOTAL_GB` quota headroom).
The gateway build fills the **node's ephemeral disk** — Angular `node_modules`,
Maven `target/` + `~/.m2` repo, the Jib build cache, then Trivy re-pulling the
image — past the kubelet `DiskPressure` threshold, and the kubelet **evicts the
runner pod mid-run**. Unlike a **Spot reclaim** (graceful — the runner deregisters
and GitHub re-queues the one job), a `DiskPressure` eviction kills the runner
**abruptly**, so GitHub keeps the job assigned to a runner it still believes exists
and the run hangs. **Only the `githubactions` engine is affected** — Tekton/Argo
pipeline pods keep their build tree on a **PVC workspace**, not the node's ephemeral
disk.

**Fix (#541):** a best-effort **"Reclaim disk before image scan"** step in the
rendered workflow ([`jenkins/pipelines/seed/microservices-ci.yml.tmpl`](../jenkins/pipelines/seed/microservices-ci.yml.tmpl)),
right after the Jib build — the image is already in GHCR so the build tree is dead
weight. It `rm -rf`s `node_modules`/`target`/`~/.m2/repository`/the Jib cache and
`docker image prune -af`s, all `|| true` (never fails the build). This is a
**template**, not the fork's live `.github/workflows/microservices-ci.yml`, so it
takes effect only after a **re-seed** — the next **Day1** or a
[`06-githubactions-pipelines.sh`](../scripts/06-githubactions-pipelines.sh) re-run
(equivalently `Day2.redeploy.06-githubactions`). See
[404 § The ci-spot / NAP showcase](./404-GITHUB_ACTIONS.md#the-ci-spot--nap-showcase-why-this-engine-defaults-to-spot).

## OSS Grafana shows "No data" everywhere with zero datasources configured (`/api/datasources` returns `[]`)

**Symptom:** on `observability.mode=oss`, every dashboard panel shows **"No data"**
across the board (not one dashboard, ALL of them) even though Prometheus/Loki/Tempo
are demonstrably healthy and ingesting (`up{}` returns fresh samples, targets are
up). Grafana's own API confirms it has no datasources at all:

```bash
kubectl -n observability exec deploy/oss-kube-prometheus-stack-grafana -c grafana -- \
  curl -sk -u "admin:$(kubectl -n observability get secret oss-kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)" \
  https://localhost:3000/api/datasources
# []
```

The provisioning ConfigMap (`oss-kube-prometheus-stack-grafana-datasource`, labelled
`grafana_datasource=1`) is present and correct — all four datasources (Prometheus,
Loki, Tempo, Jenkins) are in there — and the `grafana-sc-datasources` sidecar
container is running normally (`"Loading incluster config..."` every minute, no
errors). Nothing in the Grafana container logs mentions an error either; there's
simply no `logger=provisioning.datasources` "starting/finished" pair the way there
is for `provisioning.dashboard`/`provisioning.alerting`.

**Cause:** a boot-time race in the `kiwigrid/k8s-sidecar` container (the chart's
default `sidecar.datasources` mechanism, `watchMethod: WATCH`). At pod start the
sidecar copies the labelled ConfigMap into the shared `/etc/grafana/provisioning/datasources`
volume and fires **one** `POST /api/admin/provisioning/datasources/reload` to tell
Grafana to load it. If that first call lands **before** Grafana's own HTTP API is
actually ready to serve it, the call is dropped — and because the sidecar only
reacts to **ConfigMap change events**, not on a timer, it never retries: the
ConfigMap never changes again, so the reload never fires again, and the datasources
stay empty **until something manually POSTs the reload endpoint** (which immediately
succeeds and populates everything — confirming the config was always valid,
it just never got applied). Unrelated to `gateway.backendTls.enabled` (docs/504)
or anything else touched in this repo — pure upstream chart timing, live-diagnosed
2026-07-06 against a pod that had been running for 3 hours with the race already
latched.

**Fix (self-healing, not just a live reload):**
[`observability/grafana/values-oss.yaml`](../observability/grafana/values-oss.yaml)
`grafana.sidecar.datasources` sets `initDatasources: true` + `skipReload: true`
— the chart's own documented mechanism for exactly this failure mode. This runs the
datasources sidecar as an **init container** instead of a long-running watcher: it
copies the file into place and exits *before* the Grafana container ever starts, so
Grafana's native boot-time provisioning loader (which runs on every single restart,
independent of any HTTP call succeeding) picks it up deterministically — no more
race, no more manual reload needed on any future pod restart. Trade-off: a future
edit to `additionalDataSources` needs a pod restart to take effect (no more live
sidecar to auto-detect the ConfigMap change) — acceptable here because nothing in
this repo pushes a *live* datasource change (unlike dashboards, which the
`grafana_dashboard` sidecar - unaffected, untouched - keeps live for the
publish-workflow use case).

> ⚠️ **Also required: `watchMethod: LIST`.** The chart's init-container template
> reuses the *same* `sidecar.datasources.watchMethod` value verbatim on the init
> container (`METHOD: {{ .Values.sidecar.datasources.watchMethod }}`) — it does
> **not** default to a one-shot mode just because `initDatasources` is true. The
> chart's own default (`watchMethod: WATCH`) makes `kiwigrid/k8s-sidecar`
> continuously watch and **never exit** — as an init container that hangs the pod
> in `Init:0/1` forever (confirmed live: Grafana's main container never started).
> `METHOD=LIST` ("list config-maps/secrets and exit", per
> [kiwigrid/k8s-sidecar's own README](https://github.com/kiwigrid/k8s-sidecar))
> is the one mode that actually terminates. If you ever see a Grafana rollout
> stuck at `Init:0/1`, this is almost certainly why — check
> `kubectl -n observability describe pod <new-grafana-pod>` for an
> `Init:0/1` / never-`Ready` init container, and confirm `watchMethod: LIST` is
> set alongside `initDatasources: true`.

**Unstick a live cluster without waiting for a redeploy:**

```bash
kubectl -n observability exec deploy/oss-kube-prometheus-stack-grafana -c grafana -- \
  curl -sk -u "admin:<admin-password>" -X POST \
  https://localhost:3000/api/admin/provisioning/datasources/reload
# {"message":"Datasources config reloaded"}
```

---

[← Previous: 901. Local Development](./901-LOCAL_DEVELOPMENT.md) | [🏠 Home](../README.md) | [→ Next: 903. Glossary](./903-GLOSSARY.md)

---

*902. Troubleshooting — jenkins-2026*
