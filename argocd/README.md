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

### `cnpg-operator` — oversized CRDs ([`cnpg-app.yaml`](cnpg-app.yaml))

CloudNative-PG's `clusters`/`poolers` CRDs carry huge OpenAPI schemas, which trips ArgoCD in two distinct places. The manifest addresses both:

- **Diff** → `argocd.argoproj.io/compare-options: ServerSideDiff=true`. A client-side diff 3-way-merges against the oversized live object and can report **false `OutOfSync`**; `ServerSideDiff` computes the diff via server-side apply on the API server, giving a reliable `Synced` status so automated sync doesn't fire a doomed sync on phantom drift.
- **Apply** → `syncOptions: [..., ServerSideApply=true, Replace=true]`. `ServerSideApply` *should* avoid the `last-applied-configuration` annotation, but **on ArgoCD v3.5 it is not honored for these CRDs** — the sync still does a client-side patch and blows the 256 KB `metadata.annotations` limit. **`Replace=true`** (`kubectl replace`, no annotation) is what actually reconciles them.

> **Cosmetic "dry run" failure.** A **manual/forced** full sync still reports `one or more objects failed to apply (dry run)`, because ArgoCD's pre-sync dry-run is client-side here regardless of the options above. This is **cosmetic**: verified live, the Application stays **Synced + Healthy**, the CRDs are correctly installed (server-side-apply-managed, 0-byte `last-applied-configuration`), and the controller **skips auto-sync while `Synced`** (`"Skipping auto-sync: application status is Synced"`). It only surfaces on a deliberate re-sync.
>
> **Never force-sync these CRDs.** `Replace` on a CRD is a `PUT` (no cascade-delete), but a force/recreate would delete & recreate the CRD and **cascade-delete the Postgres clusters**.

History: introduced with `Replace=true` (#169 initially), briefly switched to `ServerSideApply`+`ServerSideDiff`-only on the theory that it made `Replace` unnecessary, then **reverted to `Replace=true`** (#171) once live validation showed `ServerSideApply` is not honored for these CRDs on v3.5.
