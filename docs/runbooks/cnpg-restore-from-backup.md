# Runbook: restore a CNPG Postgres database from the GCS backup (base backup + WAL / PITR)

Recovers a microservices Postgres database from the **barman object-store backups**
CNPG streams to GCS — the *only* reason those backups exist, and (until now) the one
step documented nowhere. This is a **data-loss recovery** procedure: you run it to get
*old data back* after a logical corruption, an accidental `DROP`/`DELETE`, or a lost
volume — **not** as part of a normal rebuild (a rebuild deliberately starts empty; see
§1). Written for both newcomers (start at §0) and the on-call specialist reaching for
the concrete manifest (§3).

> Conceptual background: the backup *wiring* lives in [502. Microservices GitOps](../502-MICROSERVICES_GITOPS.md)
> §"pgAdmin & Database Administration" and the GitOps chart
> (`nubenetes/jenkins-2026-gitops-config`, `helm/microservices/templates/postgres.yaml`);
> the persistent bucket is created by [`terraform/bootstrap`](../../terraform/bootstrap)
> and explained in [100. Bootstrap](../100-BOOTSTRAP.md). The two *backup-failure*
> signatures this runbook cross-links are in [902. Troubleshooting](../902-TROUBLESHOOTING.md)
> ("WAL backups fail `ContinuousArchiving=False`" and "WAL archiving fails after a
> rebuild `Expected empty archive`"). This runbook is the **restore** companion those
> two sections never covered.

## Background — what is backed up, and where

Each microservice gets its own CloudNativePG `Cluster` (`postgres-gateway`,
`postgres-jhipstersamplemicroservice`) rendered by the GitOps chart's
[`templates/postgres.yaml`](https://github.com/nubenetes/jenkins-2026-gitops-config/blob/main/helm/microservices/templates/postgres.yaml).
Two things are archived, continuously, to Google Cloud Storage:

- **WAL segments** (Write-Ahead Log) — every committed change, shipped by
  `barman-cloud-wal-archive` as it is generated (gzip-compressed). This is what makes
  **point-in-time recovery (PITR)** possible.
- **Base backups** — periodic full snapshots. The chart ships a `ScheduledBackup`
  (`postgres-<svc>-daily-backup`) at `0 0 0 * * *` (daily, midnight) plus any on-demand
  `kubectl cnpg backup` you take. A restore replays WAL *on top of* the most recent base
  backup at or before your target.

Both land under a **fixed** barman path, one prefix per service:

```
gs://<project_id>-jenkins-2026-postgres-backups/<service>/
#     └─ persistent bucket (terraform/bootstrap)      └─ e.g. gateway, jhipstersamplemicroservice
#        serverName defaults to the Cluster name
```

**How the pods authenticate (no keys):** `barmanObjectStore.googleCredentials.gkeEnvironment: true`
+ a `serviceAccountTemplate` annotation make each Cluster's Kubernetes SA (`postgres-<svc>`)
impersonate the GCP SA **`<cluster_name>-pg-backups`** (e.g. `jenkins-2026-pg-backups`)
via Workload Identity. That GSA holds `roles/storage.admin` **bucket-scoped** to the
backups bucket (`storage.admin`, *not* `objectAdmin` — barman's
`barman-cloud-check-wal-archive` calls `storage.buckets.get`, which `objectAdmin` lacks;
see [`terraform/gke/main.tf`](../../terraform/gke/main.tf) `google_service_account.pg_backups`).

<details>
<summary>Why the bucket lives in the never-destroyed Day0 tier (and what that costs)</summary>

The bucket (`google_storage_bucket.postgres_backups`) is created by
[`terraform/bootstrap`](../../terraform/bootstrap/main.tf) with `force_destroy = false`,
so it **survives a Decom + Day1 rebuild** — that persistence is the entire point:
recoverability across cluster rebuilds. It is name-prefixed with the project ID
(`<project_id>-jenkins-2026-postgres-backups`) because GCS bucket names are globally
unique and a bare name would 409 on a rebuild under a new project.

Two lifecycle rules bound the retention window you can restore into:

- objects move to **Nearline** after 3 days (cost), and
- objects are **deleted after 7 days**.

So the PITR window is **~7 days**, not unbounded. A recovery target older than the
oldest surviving base backup + WAL chain is unreachable — check what actually exists in
the bucket before you promise a target (§4).
</details>

> ⚠️ Steps §0–§2 and §4's *inspection* commands are read-only. **§3 creates a new
> Cluster and §5's cutover deletes/renames the old one** — those mutate the cluster.
> Read the whole runbook before running §3.

## 0. Get cluster access (the Windows/SDK gotchas)

Same three papercuts as the other runbooks — see
[nap-spot-provisioning §0](./nap-spot-provisioning.md#0-get-cluster-access-the-gotchas-in-order)
for the long form. In short:

```bash
export CLOUDSDK_PYTHON="$HOME/AppData/Local/Google/Cloud SDK/google-cloud-sdk/platform/bundledpython/python.exe"
gcloud container clusters get-credentials jenkins-2026 --zone europe-southwest1-a   # refresh stale IP after a rebuild
kubectl --token="$(gcloud auth print-access-token)" get nodes                        # bypass the auth-plugin if missing
NS=microservices
```

The `kubectl cnpg` plugin (the CloudNativePG kubectl plugin) makes several steps easier
(`kubectl cnpg status`, `kubectl cnpg backup`). It is optional — every command below has
a plain-`kubectl` equivalent.

## 1. Decide: do you actually want to restore? (When NOT to)

A restore is the wrong tool for most situations that *look* like they need one. Rule it
out first:

| Situation | Restore? | Do this instead |
|---|---|---|
| **Cluster rebuild** (Decom + Day1) and the DB came back empty | **No — by design** | A rebuild bootstraps a **fresh `initdb`** (new system id, empty DB). `scripts/08.5-argocd.sh` even **clears the stale WAL path** on a fresh provision so archiving can start clean (see [902 § `Expected empty archive`](../902-TROUBLESHOOTING.md#cnpg-wal-archiving-fails-after-a-rebuild-expected-empty-archive)). The microservices repopulate their own schema via JHipster/Liquibase on startup. Restore **only** if you needed the *prior incarnation's rows* back. |
| **`develop` tier data gone** | **No** | The develop tier sets `global.postgresBackupEnabled: false` — it has **no backups and no HA** (disposable data). There is nothing to restore from. |
| Backups show `ContinuousArchiving=False`, app is fine | **No** | That's a *backup* fault, not data loss. Fix archiving first ([902 § `ContinuousArchiving=False`](../902-TROUBLESHOOTING.md#cnpg-postgres-wal-backups-to-gcs-fail-continuousarchivingfalse)) — you can't restore from a chain that never wrote. |
| A standby fell behind / a pod crashed | **No** | CNPG self-heals: it re-clones standbys from the primary and reschedules pods. Check `kubectl cnpg status postgres-<svc> -n microservices` first. |
| **Accidental `DROP TABLE` / bad migration / logical corruption** | **Yes** | PITR to a target *just before* the bad statement (§3–§4). |
| **Lost the primary's PV *and* all standbys** (no healthy replica to promote) | **Yes** | Full recovery from the latest base backup + WAL (§3). |

> The single most important line here: **a rebuild starting empty is expected, not a
> failure.** Reaching for a restore every time the DB is empty after a Day1 will replay
> stale data over a cluster that was supposed to be fresh. Restore is for getting
> *specific lost rows* back.

## 2. Confirm the backups you're about to restore from exist and are usable

Before creating anything, prove the chain is there and the identity works.

```bash
# a) List what's in the barman prefix for the service (base backups live under base/, WAL under wals/):
gsutil ls "gs://${PROJECT_ID}-jenkins-2026-postgres-backups/gateway/"
gsutil ls "gs://${PROJECT_ID}-jenkins-2026-postgres-backups/gateway/base/"   # → one dir per base backup, newest = latest restorable snapshot

# b) Ask CNPG what it believes the recoverability window is (needs the plugin):
kubectl cnpg status postgres-gateway -n "$NS" | grep -iE 'First Point|Last Successful|Working WAL|Continuous'
# 'First Point of Recoverability' = earliest PITR target; 'Last Successful Backup' = newest base backup.

# c) Same numbers, plugin-free, from the metrics the dashboard uses:
#    cnpg_collector_first_recoverability_point (epoch) and _last_available_backup_timestamp.
```

If the `base/` listing is empty or the *First Point of Recoverability* is unset, **stop**
— there is nothing to restore from (the backup chain never completed; go fix archiving
via 902 first). Remember the **7-day** bucket retention (§Background details): a target
older than the oldest `base/` snapshot is unreachable.

## 3. Restore — CNPG `bootstrap.recovery` from the object store

CNPG restores by **creating a *new* `Cluster`** that bootstraps itself from the object
store, rather than mutating the damaged one. You define an `externalClusters` entry
pointing at the barman path, then `bootstrap.recovery` sources from it. Two design
constraints drive the manifest below:

- **Reuse the same Cluster name** (`postgres-gateway`) — or, if you must run the
  recovery cluster alongside the old one, name it `postgres-gateway` only after you've
  removed the old one (§5). This is **not cosmetic**: the Workload-Identity binding is
  keyed on the KSA name `postgres-<svc>` in
  [`terraform/gke`](../../terraform/gke/main.tf) (`for_each = ["postgres-gateway",
  "postgres-jhipstersamplemicroservice"]`). A recovery Cluster with a *different* name
  gets a KSA that **has no GCS access**, so it can neither read the backup nor resume
  archiving. If you genuinely need a new name, add its KSA to that `for_each` and
  `Day1`-apply first.
- **Point `externalClusters[].barmanObjectStore` at the *source* prefix** and set
  `serverName` to the **name the backup was written under** (the old Cluster name), while
  the new Cluster's own archiving writes under its own name. When restoring in place
  under the same name, both are `postgres-gateway`.

Because the DB is GitOps-managed by the `microservices` ApplicationSet, the safest path
is **not** to hand-edit the live Cluster (ArgoCD would revert it). Instead:

**Option A — restore in place through GitOps (durable, preferred for a real recovery).**
Add a `recovery` bootstrap + `externalClusters` block to the chart's `postgres.yaml` in
the GitOps repo (behind a value so it's opt-in), or parameterize it via
[`argocd/microservices-appset.yaml`](../../argocd/microservices-appset.yaml) helm
parameters, then let ArgoCD apply it. Use this when the outage is real and you want the
restored cluster to *be* the managed one going forward.

**Option B — out-of-band recovery Cluster (faster, for surgical PITR / verification).**
Temporarily stop ArgoCD from fighting you, apply a standalone recovery manifest, verify,
then cut over (§5) and re-enable sync. Disable auto-sync on the app first:

```bash
kubectl -n argocd patch application microservices-stable --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

Then apply the recovery Cluster (adjust `<service>` and the target in §4):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-gateway          # MUST match an entry in terraform/gke pg_backups_wi (KSA access)
  namespace: microservices
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18.3-system-trixie   # match the running major/minor
  instances: 3                    # stable HA; use 1 for a throwaway verification cluster
  storage:
    size: 1Gi
    storageClass: premium-rwo
  walStorage:
    size: 1Gi
    storageClass: premium-rwo

  # Impersonate the same GSA the original used (Workload Identity), so the new pods
  # can READ the object store to recover AND WRITE their own new archive afterwards.
  serviceAccountTemplate:
    metadata:
      annotations:
        iam.gke.io/gcp-service-account: jenkins-2026-pg-backups@<project_id>.iam.gserviceaccount.com

  bootstrap:
    recovery:
      source: postgres-gateway-backup      # -> the externalClusters entry below
      # --- PITR target (OPTIONAL): omit both to recover to the END of the WAL chain ---
      # recoveryTarget:
      #   targetTime: "2026-07-04 18:22:00+00"   # restore to just BEFORE the bad statement
      #   # or: targetLSN, targetXID, targetName (a pg_create_restore_point label)

  externalClusters:
    - name: postgres-gateway-backup
      barmanObjectStore:
        destinationPath: gs://<project_id>-jenkins-2026-postgres-backups
        serverName: gateway                 # the PREFIX/serverName the backup was written under
        googleCredentials:
          gkeEnvironment: true
        wal:
          compression: gzip                 # must match how it was archived

  # After recovery, THIS cluster continues archiving under its own name. When restoring
  # in place, keep the same prefix so the chain continues; see §6 for the 'Expected
  # empty archive' gotcha if you recover under a name whose prefix already holds WALs.
  backup:
    barmanObjectStore:
      destinationPath: gs://<project_id>-jenkins-2026-postgres-backups/gateway
      googleCredentials:
        gkeEnvironment: true
      wal:
        compression: gzip
```

```bash
kubectl apply -f recovery-postgres-gateway.yaml
```

<details>
<summary>Notes on the manifest (read before adapting it)</summary>

- `destinationPath` in `externalClusters` is the **bucket root** and `serverName` selects
  the `<service>` sub-prefix; CNPG joins them to `gs://…/gateway/`. (The live `backup`
  block in the chart instead puts the service *in* `destinationPath` — both reach the same
  path; keep them consistent for the cluster's *own* new archive.)
- `imageName` must be **≥** the major version the backup was taken with — you can restore
  forward across minors, never backward. Match the running
  `ghcr.io/cloudnative-pg/postgresql:18.3-system-trixie` unless you're deliberately
  upgrading.
- Operator is **v1.30.0** (chart `0.29.0`, see
  [`argocd/platform-postgres/values.yaml`](../../argocd/platform-postgres/values.yaml));
  the `bootstrap.recovery` + `externalClusters` API above is stable in that release.
- The app/superuser secrets (`postgres-gateway-app`, `postgres-gateway-superuser`) are
  **regenerated** on a fresh recovery cluster unless you also restore/point them; app
  pods read the password from `postgres-gateway-app`, which CNPG recreates — expect the
  application-user password to **rotate** (see [502 § Retrieving the application-user
  passwords](../502-MICROSERVICES_GITOPS.md#retrieving-the-application-user-passwords-the-pgadmin-connections)).
</details>

## 4. Choosing the PITR target

- **Recover to the latest data** (default): omit `recoveryTarget` entirely — CNPG replays
  the full WAL chain to the end. Use this for a lost-volume recovery where you want
  *everything* back.
- **Recover to a point in time** (the usual reason to restore): set exactly one
  `recoveryTarget.target*`:
  - `targetTime: "YYYY-MM-DD HH:MM:SS+00"` — restore to just **before** the destructive
    statement. Pick a timestamp a few seconds *earlier* than the incident; you can't
    replay past a target and rewind.
  - `targetLSN` / `targetXID` — when you know the exact log position or transaction id
    (e.g. from `pg_waldump` or audit logs) and need to land on a transaction boundary.
  - `targetName` — if someone had run `SELECT pg_create_restore_point('before-migration')`
    beforehand (rare, but the cleanest target).
- The target must fall **inside** the recoverability window from §2 (≥ *First Point of
  Recoverability*, and the base backup at/just-before the target must still exist under
  the 7-day retention).

## 5. Cut over and re-enable GitOps

For **Option B** (out-of-band cluster), once §6 verification passes:

1. Point the app at the recovered cluster. If the recovery Cluster reused the name
   `postgres-gateway`, the service DNS (`postgres-gateway-rw.microservices.svc`) already
   resolves to it and app pods reconnect after a `rollout restart deploy/gateway`.
2. Re-enable ArgoCD auto-sync so drift management resumes:
   ```bash
   kubectl -n argocd patch application microservices-stable --type merge \
     -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```
   If you recovered *out of band* under the same name, make sure the chart's rendered
   Cluster now matches (Option A) — otherwise selfHeal will try to reconcile it back to
   the chart's `initdb` bootstrap. **The durable end state is always the GitOps chart
   describing the cluster you want**; Option B is a bridge, not a destination.

## 6. Verify the restore

Watch the recovery reach `Cluster in healthy state`, then confirm on the dashboard:

```bash
# Bootstrap progress (recovering -> healthy):
kubectl cnpg status postgres-gateway -n "$NS"
kubectl -n "$NS" get cluster postgres-gateway -o jsonpath='{.status.phase}{"\n"}'
#   → "Cluster in healthy state"
kubectl -n "$NS" get pods -l cnpg.io/cluster=postgres-gateway
#   → primary + standbys Running

# Spot-check the data actually came back (superuser via the primary pod):
kubectl -n "$NS" exec -it postgres-gateway-1 -- psql -U postgres -d gateway \
  -c "SELECT count(*) FROM <a_table_you_expect>;"
```

Then the **`CI-CD / PostgreSQL (CloudNativePG)`** dashboard (uid `inllvhz`,
[`observability/grafana/dashboards/postgres-overview.json`](../../observability/grafana/dashboards/postgres-overview.json)),
scoped to `namespace=microservices`:

- **Instances Up** (`cnpg_collector_up`) = your instance count; **Streaming replicas** >
  0 and **replication lag** low → the standbys re-cloned from the recovered primary.
- **WAL archiving & backups** row: **Time since last successful backup** shows a real
  value (not "no backups configured") and the **archiving-failure** age stays 0 once the
  recovered cluster resumes `ContinuousArchiving=True`.

```bash
kubectl -n "$NS" get cluster postgres-gateway \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' | grep -i archiv
#   → ContinuousArchiving=True   (archiving resumed under the cluster's own name)
```

## 6b. The `serverName` / system-id gotcha (`Expected empty archive`)

The one failure class that ambushes a restore: if the recovered cluster starts archiving
into a prefix that **already holds another incarnation's WALs**, CNPG's
`barman-cloud-check-wal-archive` refuses to mix two WAL streams and fails with
**`ERROR: WAL archive check failed for server <cluster>: Expected empty archive`** —
`ContinuousArchiving` never flips to `True` and no *new* backups are taken (the restored
data is fine; only ongoing protection is broken).

This is the **exact same safety check** documented in
[902 § "CNPG WAL archiving fails after a rebuild (`Expected empty archive`)"](../902-TROUBLESHOOTING.md#cnpg-wal-archiving-fails-after-a-rebuild-expected-empty-archive)
— read it for the full cause. In a restore it bites when you recover under a name/prefix
whose archive isn't empty. Options, cheapest first:

- **Recover in place under the same `serverName`** and let it *continue* the existing
  chain — the check passes because the new WAL segments extend the same server's stream.
- If you must start a clean archive for the restored cluster, empty the destination
  prefix by hand first (the CI SA / `*-pg-backups` GSA has `storage.admin` on the bucket):
  ```bash
  # destroys the orphaned WALs of the PRIOR incarnation under this prefix
  gsutil -m rm -r "gs://${PROJECT_ID}-jenkins-2026-postgres-backups/gateway/**"
  ```
  ⚠️ Do this **only after** the recovery has finished reading everything it needs — this
  deletes the very backups you just restored from. Take a fresh base backup immediately
  after so you regain a recoverability point:
  ```bash
  kubectl cnpg backup postgres-gateway -n "$NS"
  ```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Recovery Cluster stuck `Bootstrapping`, pod logs show `403 … does not have storage.buckets.get` | recovery Cluster's KSA name isn't in `terraform/gke` `pg_backups_wi`, or the GSA has `objectAdmin` not `admin` | reuse an existing `postgres-<svc>` name (§3), or add the new name to the `for_each` and `Day1`-apply; the GSA needs `roles/storage.admin` bucket-scoped |
| `Expected empty archive` after recovery | archiving into a prefix that already holds WALs (§6b) | recover in place under the same `serverName`, or empty the prefix + take a fresh base backup |
| `barman-cloud-... "Project was not passed and could not be auto-detected"` | the KSA got no GCP identity (WI annotation missing/wrong project) | this is the [902 auth-side `ContinuousArchiving=False`](../902-TROUBLESHOOTING.md#cnpg-postgres-wal-backups-to-gcs-fail-continuousarchivingfalse) case — fix the `serviceAccountTemplate` annotation / helm params, re-`Day1` |
| target time returns *earlier* data than expected, or fails | target predates the oldest surviving base backup (7-day retention) | pick a target inside the window from §2; older data is already lifecycle-deleted |
| app pods `CrashLoopBackOff` with auth errors after cutover | the app-user password rotated on the fresh recovery cluster | `rollout restart deploy/<svc>` so pods re-read `postgres-<svc>-app` (§3 notes) |
| ArgoCD keeps reverting the recovery Cluster to an empty `initdb` | selfHeal reconciling to the chart, which still describes a fresh bootstrap | make the chart describe the recovered cluster (Option A) before re-enabling auto-sync (§5) |

## Related

- [502. Microservices GitOps § pgAdmin & Database Administration](../502-MICROSERVICES_GITOPS.md#pgadmin--database-administration) — the DB topology, per-tier database inventory, break-glass superuser access.
- [902. Troubleshooting](../902-TROUBLESHOOTING.md) — the two backup-*failure* signatures this restore cross-links (`ContinuousArchiving=False`, `Expected empty archive`).
- [100. Bootstrap](../100-BOOTSTRAP.md) — why the backups bucket lives in the never-destroyed Day0 tier.
