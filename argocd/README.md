# Argo CD v3.5 Configuration

This directory contains manifests and configurations for deploying and managing Argo CD.

## Argo CD 3.5.x Upgrade & Breaking Changes Reference

Upgrading to Argo CD v3.5 introduces several structural modifications. Custom integrations, external plugins, and custom gRPC API clients must remediate their setups to be compatible with the 3.5 runtime environment.

### 1. React 19 UI Compliance
*   **The Change**: Argo CD's web console has been modernized to use **React 19**.
*   **Impact**: Custom UI extensions or dashboard plugins packaged with older React versions (e.g. React 16/17/18) will hit runtime errors and render failures.
*   **Remediation**: Custom extension builders must upgrade their peer dependencies, migrate to React 19, and refactor any deprecated component APIs.

### 2. Deprecation of Legacy GnuPG Signature Fields
*   **The Change**: The legacy GnuPG commit signature verification fields in the `Application` manifest have been deprecated in favor of the new **Source Integrity Result** subsystem.
*   **Impact**: Specifying legacy signature verification fields in Application specs will emit deprecation warnings and fail in strict validation modes.
*   **Remediation**: Platform engineers must update pipelines and Application manifests to utilize the new Source Integrity specifications for validating Git source repositories.

### 3. gRPC EventList Compilation Schema
*   **The Change**: The protobuf and gRPC interfaces for tracking cluster events compile with a revised `EventList` schema in version 3.5.
*   **Impact**: External custom gRPC clients (like custom dashboard metrics collectors, CI runners, or Slack notifier integrations) compiled against older Argo CD protobufs will fail to serialize/deserialize API streams, leading to connection drops or invalid payload exceptions.
*   **Remediation**: Custom clients must re-compile their API client stubs using the `v3.5.x` protobuf definitions.

---

## Patch Watcher Service

The `argocd-version-patch-watcher` CronJob is deployed to run daily at midnight. It queries GitHub Releases for new `v3.5.x` releases, compares them to the running in-cluster tags, and live-patches the deployments/statefulsets when a newer stable patch version is published.

## Applications

### `platform-postgres` — Postgres app-of-apps ([`platform-postgres-app.yaml`](platform-postgres-app.yaml) → [`platform-postgres/`](platform-postgres))

The CloudNative-PG operator and the **pgAdmin** UI that administers its databases share a lifecycle, so they are grouped under one parent `Application` (applied by `scripts/08.5-argocd.sh`). The parent renders the Helm chart [`platform-postgres/`](platform-postgres) into two children — `cnpg-operator` (chart) and `pgadmin` (this repo's `helm/pgadmin`, branch from the parent's `helm.parameters`). Teardown deletes the parent (cascade-prune via the resources finalizer). The `cnpg-operator` child needs the oversized-CRD handling below.

#### `cnpg-operator` — oversized CRDs ([`platform-postgres/templates/cnpg-operator.yaml`](platform-postgres/templates/cnpg-operator.yaml))

CloudNative-PG's `clusters`/`poolers` CRDs carry huge OpenAPI schemas, which trips ArgoCD in two distinct places. The manifest addresses both:

- **Diff** → `argocd.argoproj.io/compare-options: ServerSideDiff=true`. A client-side diff 3-way-merges against the oversized live object and can report **false `OutOfSync`**; `ServerSideDiff` computes the diff via server-side apply on the API server, giving a reliable `Synced` status so automated sync doesn't fire a doomed sync on phantom drift.
- **Apply** → `syncOptions: [..., ServerSideApply=true, Replace=true]`. `ServerSideApply` *should* avoid the `last-applied-configuration` annotation, but **on ArgoCD v3.5 it is not honored for these CRDs** — the sync still does a client-side patch and blows the 256 KB `metadata.annotations` limit. **`Replace=true`** (`kubectl replace`, no annotation) is what actually reconciles them.

> **Cosmetic "dry run" failure.** A **manual/forced** full sync still reports `one or more objects failed to apply (dry run)`, because ArgoCD's pre-sync dry-run is client-side here regardless of the options above. This is **cosmetic**: verified live, the Application stays **Synced + Healthy**, the CRDs are correctly installed (server-side-apply-managed, 0-byte `last-applied-configuration`), and the controller **skips auto-sync while `Synced`** (`"Skipping auto-sync: application status is Synced"`). It only surfaces on a deliberate re-sync.
>
> **Never force-sync these CRDs.** `Replace` on a CRD is a `PUT` (no cascade-delete), but a force/recreate would delete & recreate the CRD and **cascade-delete the Postgres clusters**.

History: introduced with `Replace=true` (#169 initially), briefly switched to `ServerSideApply`+`ServerSideDiff`-only on the theory that it made `Replace` unnecessary, then **reverted to `Replace=true`** (#171) once live validation showed `ServerSideApply` is not honored for these CRDs on v3.5.

### `observability-oss` — OSS observability app-of-apps ([`observability-oss-app.yaml`](observability-oss-app.yaml) → [`observability-oss/`](observability-oss))

Only applied when `observability.mode=oss` (by `scripts/03-observability.sh`). The parent `Application` renders the local Helm chart [`observability-oss/`](observability-oss), which emits three child `Application`s — `oss-kube-prometheus-stack` (Prometheus + Grafana), `oss-loki`, `oss-tempo`. Each is **multi-source**: the upstream chart plus this repo's `observability/grafana/values-oss*.yaml` (referenced via `$values`). Chart versions are pinned in [`observability-oss/values.yaml`](observability-oss/values.yaml); `repoURL`/`targetRevision` are passed down from the parent's `helm.parameters` (set from `J2026_SELF_REPO_URL`/`_BRANCH`).

- **App-of-apps as a Helm chart** (not a plain directory) so the dynamic repo/branch/version flow down to the children — a plain directory app can't template per-environment values.
- **`ServerSideApply=true`** on `oss-kube-prometheus-stack` for the same oversized-CRD reason as `cnpg-operator` (the Prometheus operator CRDs).
- **Companion inputs stay script-managed** (not in any app, so ArgoCD never owns/prunes them): the `jenkins-2026-grafana-dashboards` ConfigMap (Grafana sidecar), the `grafana-jenkins-ds` Secret (`$JENKINS_API_TOKEN`) and the `grafana-runtime-config` ConfigMap (`GF_SERVER_ROOT_URL`), all created by `scripts/03-observability.sh` and consumed via the chart's sidecar / `grafana.envValueFrom` (all `optional: true`).
- **Teardown**: deleting the parent `Application` cascade-prunes the charts via the `resources-finalizer.argocd.argoproj.io` on each child; `scripts/down.sh` (oss) does this *before* uninstalling ArgoCD, and a mode switch away from oss removes it via `remove_oss_observability_app` in `scripts/03-observability.sh`.
- **Day-2 refresh**: [`Day2.publish.01-oss-grafana`](../.github/workflows/Day2.publish.01-oss-grafana.yml) rebuilds the dashboards ConfigMap, nudges a re-sync and republishes alerts without a reprovision.
