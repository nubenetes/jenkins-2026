[← Previous: 103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md) | [🏠 Home](../README.md) | [→ Next: 201. Architecture](./201-ARCHITECTURE.md)

---

# 104. Rebuild-Safety — surviving `Decom` + `Day1`

> **TL;DR** — In this PoC, **`Decom` (teardown) + `Day1` (fresh provision) is a routine, repeated operation, not a one-off.** A resource is *rebuild-safe* when a **fresh incarnation never collides with a prior incarnation's leftover state**, and **teardown never leaves residue that blocks the next build**. The vast majority of the platform is rebuild-safe **by design** — the [master matrix](#4-the-rebuild-safety-matrix-safe-by-design) below names the exact mechanism for each persistent/external resource. A system-wide audit found a handful of gaps of the *"works until the first rebuild"* kind; all are [closed](#5-the-gaps-that-were-closed) (PRs [#487](https://github.com/nubenetes/jenkins-2026/pull/487)–[#489](https://github.com/nubenetes/jenkins-2026/pull/489)).

---

## 1. Why this matters — the lifecycle

The GKE cluster is **throwaway**: `Decom.cluster.01-gke` tears it (VPC, node pool, workloads) down to stop charges, and `Day1.cluster.01-gke` stands a **fresh** one up. Both are idempotent and run repeatedly (see [101](./101-GITHUB_ACTIONS_WORKFLOWS.md)). Some immutable cluster fields (Dataplane V2, WireGuard) even force a **destroy+recreate within a single `Day1`**. So every resource must tolerate *"the cluster/workload it belonged to was destroyed and a brand-new one took its place."*

Not everything dies with the cluster. Three **persistence tiers** coexist:

| Tier | Survives `Decom.cluster`? | Created / destroyed by | Examples |
|---|---|---|---|
| **Root of trust** (Day0, human) | ✅ yes — destroyed only by `bootstrap.sh down` | [`terraform/bootstrap`](../terraform/bootstrap/) via [`scripts/bootstrap.sh`](../scripts/bootstrap.sh) | TF **state bucket**, WIF/OIDC trust + CI SA, permanent **DNS zone**, **Postgres backups bucket** |
| **Persistent backends** (Day0 infra) | ✅ yes — destroyed only by the matching `Decom.infra.0N` | `Day0.infra.01–04` / `Decom.infra.01–04` | gateway static **IP** + wildcard **cert**, **Grafana Cloud stack**, **Azure**/**AWS** managed backends |
| **Cluster-scoped** (ephemeral) | ❌ no — dies with the cluster | `Day1.cluster.01` / `Decom.cluster.01` | GKE cluster/VPC/node pool, all K8s workloads, `grafana-cloud-token` |
| **External / out-of-band** | ✅ persists independently | GitHub / SaaS, not fully Terraform-managed | **ghcr** image registry, the **GitOps config repo**, the Grafana Cloud **org/free tier**, the **IAP OAuth brand** |

The rebuild-safety problem lives at the **boundary**: a *cluster-scoped* fresh incarnation talking to a *persistent* or *external* resource that still holds the **previous** incarnation's state.

---

## 2. The bug class — two failure modes

Every rebuild-safety defect is one of two shapes:

- **(A) COLLISION** — a persistent/external resource with a **FIXED identity** (name / path / slug / issuer URL) that a fresh incarnation **expects clean/empty/available** but finds **occupied by a prior incarnation's stale state** → conflict, `already exists`, `Expected empty archive`, reserved-name cooldown, dangling ID.
- **(B) RESIDUE** — **teardown leaves orphaned resources** that **block or corrupt the next rebuild** → finalizer deadlocks, orphaned disks/IPs/bindings, a stale state lock, leftover cloud resources.

Both share a signature: **the first-ever provision works; the break only appears on rebuild #2+.**

### The exemplar (mode A) — CNPG Postgres WAL archive

The bug that started this whole thread, now the canonical example:

1. Every `Day1` bootstraps the CNPG clusters via **fresh `initdb`** — a new PostgreSQL *system identifier*.
2. Their barman WAL/backup path is **fixed** (`gs://<project>-jenkins-2026-postgres-backups/<service>`; `serverName` defaults to the cluster name), and the backups bucket is a **persistent Day0** resource that **survives Decom**.
3. Nothing emptied that path on teardown.
4. → On rebuild, CNPG's `barman-cloud-check-wal-archive` — a safety check that refuses to mix two clusters' WAL streams — finds the prior incarnation's WALs and fails with **`Expected empty archive`**. `ContinuousArchiving=False`, backups stuck `walArchivingFailing`, the dashboard reads *"no backups configured"* forever.

**Fix** ([#487](https://github.com/nubenetes/jenkins-2026/pull/487)): [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) clears the stale archive on a **fresh provision only** (guarded: runs before the ApplicationSet creates the clusters, and only when **no live CNPG `Cluster` exists**, so a re-run never touches a running cluster's backups). See [902 § WAL archiving fails after a rebuild](./902-TROUBLESHOOTING.md).

---

## 3. The rebuild-safety design patterns (the toolbox)

The audit surfaced a small, **reusable set of mechanisms** that make a resource rebuild-safe. New persistent/external resources should reach for one of these:

| Pattern | What it does | Where it's used |
|---|---|---|
| **Random-suffix name** | A `random_string` (no `keepers`) baked into the name/slug — stable on re-apply, *fresh* only on destroy+recreate → dodges reserved-name **cooldowns** | Grafana Cloud stack **slug** |
| **Globally-unique name** | Project-prefixed name → never collides in a shared global namespace (409) | TF state bucket, backups bucket |
| **`ignore_changes` on ForceNew** | Stops a drifting field (autoscaler node count) from destroy/recreating a resource on an idempotent re-run | GKE static node pool `initial_node_count` ([#429](https://github.com/nubenetes/jenkins-2026/pull/429)) |
| **Deterministic-from-inputs** | The value is a pure function of fixed inputs → identical across incarnations, so re-apply is a no-op | AWS/Azure OIDC **issuer URL** (from project/location/cluster-name), cert-validation CNAME (from `base_domain`) |
| **Reconcile-to-current** | Persistent record is idempotently repointed at the new incarnation's value | wildcard-A record → current gateway IP |
| **Idempotent describe-then-create** | Check-then-create; adopt what exists | `provision_secret` (Secret Manager), ArgoCD apply |
| **Guarded fresh-provision cleanup** | Clear the persistent path **only** when no live consumer exists | Postgres WAL clear ([#487](https://github.com/nubenetes/jenkins-2026/pull/487)) |
| **Tombstone adoption** | `create_ignore_already_exists` — adopt a soft-deleted resource instead of 409-ing | GKE GSAs ([#488](https://github.com/nubenetes/jenkins-2026/pull/488)) |
| **Never-prune-a-live-reference** | Retention deletes only *untagged* manifests, never a tag the GitOps repo might pin | ghcr retention ([#488](https://github.com/nubenetes/jenkins-2026/pull/488)) |
| **Entropy in build tags** | App-source SHA appended so a reset `BUILD_NUMBER` can't re-mint an existing tag | Jenkins `IMAGE_TAG` ([#488](https://github.com/nubenetes/jenkins-2026/pull/488)); Tekton random run suffix |
| **Concurrency + stale-lock cleanup** | Per-state-prefix concurrency group + pre-`init` `.tflock` removal | all state workflows ([#488](https://github.com/nubenetes/jenkins-2026/pull/488)/[#489](https://github.com/nubenetes/jenkins-2026/pull/489)) |
| **Cluster-alive teardown ordering** | Release cloud LB/NEG chains **while the cluster is still up**, before the VPC delete | `down.sh` |
| **Force-finalize** | Strip finalizers / force-unlock etcd-only objects stuck `Terminating` | `drain_namespace`, `retire_ci_engine` |

---

## 4. The rebuild-safety matrix (safe-by-design)

Every persistent/external resource, its tier, and the **exact mechanism** that makes a rebuild safe. *(Cluster-scoped resources that simply die and are recreated in one self-contained state are omitted — they have no cross-incarnation surface.)*

### 4.1 Terraform state & object stores

| Resource | Rebuild-safe? | Mechanism |
|---|---|---|
| **TF remote-state bucket** (`terraform/bootstrap`) | ✅ | Globally-unique **project-prefixed** name (no 409) + object versioning + `force_destroy=false` + `reconcile_imports()` **adoption** on re-seed. Residue is intentional (root of trust). |
| **Per-module state prefixes** (`gke`, `gateway-bootstrap`, `grafana-cloud-*`, `azure-`, `aws-`) | ✅ | One **unique prefix per module** → no cross-module clobber; clean re-init per prefix. |
| **`backend_override.tf`** (CI-written) | ✅ | **Gitignored** + written at runtime from `TF_STATE_BUCKET` with the module's unique prefix → never a committed/foreign-bucket pin. |
| **Postgres backups bucket** (`terraform/bootstrap`) | ✅ *(fixed [#487](https://github.com/nubenetes/jenkins-2026/pull/487))* | Persistent + fixed name, but the barman WAL path is **cleared on fresh provision** (guarded) so `barman-cloud-check-wal-archive` sees an empty archive. See [§2](#the-exemplar-mode-a--cnpg-postgres-wal-archive). |
| **State lock** (`default.tflock`) | ✅ *(fixed [#489](https://github.com/nubenetes/jenkins-2026/pull/489))* | Shared [`tf-remove-stale-lock`](../.github/actions/tf-remove-stale-lock/action.yml) composite action removes a lock left by a cancelled run **before `init`** in every state workflow; per-prefix **concurrency** prevents two live runs contending. |

### 4.2 GKE cluster (single self-contained state — destroy→recreate leaves no trace)

| Resource | Rebuild-safe? | Mechanism |
|---|---|---|
| **`initial_node_count` drift** | ✅ | `lifecycle.ignore_changes` ([#429](https://github.com/nubenetes/jenkins-2026/pull/429)) — the autoscaler's count doesn't ForceNew the pool on a `Day1` re-run. |
| **`datapath_provider` / `in_transit_encryption_config`** | ✅ | Immutable, but **hardcoded constants** → an idempotent re-run never triggers a recreate; a rebuild is a clean create. |
| **VPC/subnet, node SA, cluster, node pool, WI bindings** | ✅ | Fixed-name but all in the **same self-contained state** → destroy+recreate cycle, no external fixed-path reuse. |

### 4.3 DNS / gateway (persistent, fixed-name, reconcile-to-current)

| Resource | Rebuild-safe? | Mechanism |
|---|---|---|
| **Global static IP** `jenkins-2026-gateway-ip` | ✅ | Lives only in `gateway-bootstrap` state; `terraform/gke` never touches it → survives cluster Decom unchanged; the Gateway re-binds by **NamedAddress**. |
| **In-cluster L7 LB / forwarding-rule** | ✅ | `down.sh` releases the whole chain (forwarding-rule → … → NEG) **while the cluster is alive**, before the VPC is destroyed → the IP returns to reserved-unused; the next Gateway re-binds cleanly. |
| **Wildcard-A record** | ✅ | `rrdatas = [gateway_ip.address]`, same state as the IP → still resolves; the umbrella reconcile is an idempotent no-op. |
| **Cert Manager** (`-dns-auth` / `-cert` / `-cert-map`) + validation CNAME | ✅ | Destroy removes them from GCP (`certificatemanager.owner` chosen so `.delete` succeeds); the CNAME data is **deterministic from `base_domain`** → recreate is identical. |
| **Permanent DNS zone** `jenkins-2026-public-zone` | ✅ | In `terraform/bootstrap`; destroyed only by the human `bootstrap.sh down`. Nameservers / the one-time parent `NS` delegation **never change**. |

### 4.4 Identity / secrets

| Resource | Rebuild-safe? | Mechanism |
|---|---|---|
| **IAP OAuth brand + client** | ✅ | A manual, one-time **Console singleton** — never created/deleted by any code; a rebuild only re-injects the same GitHub secret values. |
| **GCP Secret Manager** secrets | ✅ | `provision_secret` is **describe-then-create idempotent**; Secret Manager has **NO tombstone** (immediately re-creatable); generated values are kept stable across rebuilds. |
| **ClusterSecretStore + ExternalSecrets** (ESO) | ✅ | Die with the cluster (no cross-rebuild residue); idempotent re-apply; the retire path sets `deletionPolicy=Retain` + strips ownerRefs. |
| **GKE GSAs** (`*-nodes`, `eso-secret-reader`, `*-pg-backups`) | ✅ *(fixed [#488](https://github.com/nubenetes/jenkins-2026/pull/488))* | Fixed `account_id` destroyed+recreated by Decom/Day1, and a deleted GSA is **tombstoned ~30 days** — `create_ignore_already_exists = true` **adopts** the tombstone instead of 409-ing. |
| **GitHub Actions secrets/vars** | ✅ | Pure inputs — no cluster-lifecycle writeback. |

### 4.5 Observability backends (persistent Day0 — idempotent no-op re-apply)

| Resource | Rebuild-safe? | Mechanism |
|---|---|---|
| **Grafana Cloud slug** | ✅ | `random_string.slug_suffix` (no `keepers`) persisted in state → **stable** on re-apply, fresh only on destroy+recreate → defeats the **reserved-slug cooldown**; `delete_protection=false`. |
| **AWS `GKE→AWS` OIDC provider** | ✅ | Issuer URL is **deterministic** from the fixed project/location/cluster-name → unchanged across rebuild; in persistent state, `Day1` re-applies as a no-op. |
| **Azure Managed Grafana / Monitor / DCE-DCR / SP** | ✅ | Persistent state, not touched by cluster Decom; the `Day1` preflight is an idempotent no-op; the SP password lives in state (never re-minted on rebuild). |
| **AWS AMP / AMG / CloudWatch / IAM** | ✅ | Same persistent-state, no-op-on-rebuild model; fixed account-unique names never destroy+recreate on a **cluster** rebuild. |
| **`grafana-cloud-token`** (per-cluster) | ✅ *(guard [#489](https://github.com/nubenetes/jenkins-2026/pull/489))* | Cluster-scoped: destroyed+recreated in lockstep with the cluster. `Decom.infra.02` now **aborts** if run standalone while this token state still references the stack, forcing `Decom.cluster`-first order. |

### 4.6 Teardown residue (`down.sh` / `Decom`, idempotent, cluster-alive ordering)

| Resource | Rebuild-safe? | Mechanism |
|---|---|---|
| **NEGs** (`neg-finalizer` on svcneg) | ✅ | **3-layer teardown**: finalizer-wait (L1) + async-poll (L2) + dependency-ordered force-delete (L3) — all **before** the VPC destroy. |
| **External L7 LB chain** | ✅ | Fixed-name deletes + finalizer-wait release the GCP LB; L3 dependency-ordered backstop; works from a fresh CI checkout. |
| **CSI PV disks** | ✅ *(cost only)* | Labeled-disk sweep with detach-race retry (cost residue only — never blocks a rebuild). |
| **Namespaces stuck `Terminating`** | ✅ | `drain_namespace` force-finalizes etcd-only objects; app-of-apps deleted first while ArgoCD is alive (cascade-prune). |
| **CNPG PDBs** (0 disruptions) | ✅ | Deleted up-front + post-cascade + scale-to-zero so a node-pool drain never blocks; 60m delete timeout. |
| **CI-engine switch residue** | ✅ | `retire_ci_engine` deletes the sibling engine's parent+child apps, clears NEG finalizers, deletes owned namespaces; idempotent no-op when the engine is absent. |
| **ArgoCD control-plane state** | ✅ | In-cluster only → clean on rebuild; `08.5` is idempotent (pending-release recovery, pre-delete CMs to dodge SSA conflicts, a fresh CI token each run). |

### 4.7 Registry / GitOps / CI

| Resource | Rebuild-safe? | Mechanism |
|---|---|---|
| **ghcr image tags** vs the GitOps pin | ✅ *(fixed [#488](https://github.com/nubenetes/jenkins-2026/pull/488))* | A fresh `Day1` deploys the tag pinned in the **persistent** gitops-config repo *without* rebuilding, so `Day2.registry.01` now prunes **only untagged** manifests — never a still-pinnable tag. |
| **Jenkins image tag** (`<branch>-<build#>`) | ✅ *(fixed [#488](https://github.com/nubenetes/jenkins-2026/pull/488))* | `BUILD_NUMBER` resets to 1 on a Jenkins rebuild → the app-source **commit SHA** is appended so the tag can't mutably overwrite a prior incarnation's. (Tekton was already immune via a random run suffix.) |
| **GitOps config repo** state | ✅ | Direct-push, machine-managed image-tag bumps; a fresh cluster deploys the last pinned tags (which the two rules above keep resolvable). |

---

## 5. The gaps that were closed

The audit filed most of the system as safe-by-design and found **7 real gaps** of the collision/residue class. All are on `main`:

| # | Subsystem | Failure (the collision/residue) | Fix | PR |
|---|---|---|---|---|
| 1 | Postgres | Fresh initdb + fixed barman path + persistent bucket → `Expected empty archive` | Guarded fresh-provision WAL-path clear | [#487](https://github.com/nubenetes/jenkins-2026/pull/487) |
| 2 | Secrets | GSA soft-delete tombstone (~30d) → `Day1` 409 on the fixed `account_id` | `create_ignore_already_exists = true` (3 GSAs) | [#488](https://github.com/nubenetes/jenkins-2026/pull/488) |
| 3 | Registry | Age/count retention could GC a still-pinned tag → ImagePullBackOff on rebuild | `delete-only-untagged-versions: true` | [#488](https://github.com/nubenetes/jenkins-2026/pull/488) |
| 4 | CI | `BUILD_NUMBER` reset → re-minted/overwrote existing ghcr tags | append app-source commit SHA to `IMAGE_TAG` | [#488](https://github.com/nubenetes/jenkins-2026/pull/488) |
| 5 | State | No concurrency guard → two same-module runs contend the one state lock | per-state-prefix `concurrency` (cancel-in-progress:false) | [#488](https://github.com/nubenetes/jenkins-2026/pull/488) |
| 6 | State | Only `Decom.cluster` cleaned a stale `.tflock` → other modules wedge | shared [`tf-remove-stale-lock`](../.github/actions/tf-remove-stale-lock/action.yml) action, wired before `init` | [#489](https://github.com/nubenetes/jenkins-2026/pull/489) |
| 7 | Obs | Standalone `Decom.infra.02` destroyed the stack out-of-order vs its token | abort-guard forcing `Decom.cluster`-first | [#489](https://github.com/nubenetes/jenkins-2026/pull/489) |

---

## 6. Live-verification checklist

Code-level rebuild-safety is settled; a few items can only be *confirmed* against live cloud/registry state:

1. **GSA tombstone window** — the `create_ignore_already_exists` fix is only exercised by a real **Decom + Day1 within 30 days**; confirm the `eso-secret-reader` and `*-pg-backups` SA-create steps adopt the tombstone rather than 409-ing.
2. **ghcr pins resolvable** — the current gitops pins (`main-1` for both services at time of writing) must still exist; the `delete-only-untagged` rule guarantees this, but a `docker manifest inspect` of each `values-{stable,develop}.yaml` tag is the direct check.
3. **AWS OIDC thumbprint** — after a `container.googleapis.com` TLS-cert rotation, confirm the collector's `AssumeRoleWithWebIdentity` still succeeds (STS ignores the thumbprint for in-trust-store roots; `Day1`'s idempotent re-apply refreshes it).

---

## 7. Adding a new persistent or external resource — the checklist

Before adding anything that **outlives a cluster** (a bucket, a fixed-name cloud resource, an external SaaS object, a registry artifact), ask:

1. **Does it have a FIXED identity** (name / path / slug) a fresh incarnation will reuse? → give it a **random suffix** or a **per-incarnation token**, or make it **deterministic-from-inputs**.
2. **Does a fresh incarnation expect it EMPTY / available?** → add a **guarded fresh-provision cleanup** (only when no live consumer exists), or a reconcile-to-current, or bootstrap-from-recovery.
3. **Is it soft-deleted / cooldown'd on destroy?** (GSAs, Grafana slugs) → **adopt the tombstone** (`create_ignore_already_exists`) or dodge the cooldown (random suffix).
4. **Does teardown leave residue** (finalizers, disks, locks, cloud LB parts)? → tear it down **while the cluster is alive**, force-finalize, and clean the artifact.
5. **Is it in its own Terraform state prefix** with **concurrency + stale-lock cleanup**?
6. **Add a row to [§4](#4-the-rebuild-safety-matrix-safe-by-design)** naming the mechanism, and a [902](./902-TROUBLESHOOTING.md) entry for its failure signature.

> The invariant: **a rebuild is a create, not a merge.** If a resource can't be safely created over a prior incarnation's leftovers, it isn't rebuild-safe yet.

---

*104. Rebuild-Safety — jenkins-2026*
