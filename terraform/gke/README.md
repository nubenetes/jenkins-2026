# terraform/gke

The **throwaway GKE cluster** — the per-cluster compute the whole platform runs
on. A single zonal VPC-native cluster + one static node pool, running
**Dataplane V2** (`ADVANCED_DATAPATH`, so NetworkPolicies actually enforce) and
**WireGuard** inter-node pod encryption, with optional **Node Auto-Provisioning**
(NAP, driven by `nodeAutoProvisioning.enabled` in `config/config.yaml`) for
bursty CI agents on top of the long-lived static pool. Dataplane V2 and WireGuard
are immutable cluster fields — changing them recreates the cluster (Decom + Day1).
See [`docs/201`](../../docs/201-ARCHITECTURE.md) and [`docs/503`](../../docs/503-NETWORKING.md).

## Lifecycle owner

- **CI:** applied by `Day1.cluster.01-gke.yml`, destroyed by
  `Decom.cluster.01-gke.yml`. Applying a change = **re-run Day1** (idempotent;
  `terraform apply` no-ops when the cluster is already in state) — not Decom+Day1.
- **Local:** `test/e2e.sh` provisions and tears it down as one full lifecycle.

## State

- **CI:** GCS remote state in the bootstrap state bucket, prefix
  **`jenkins-2026/gke`** (via a `backend_override.tf` the workflows write).
- **Local (`test/e2e.sh`):** local `terraform.tfstate` (no backend override).

## Key inputs

- `project_id` (required, billing enabled), `region` (default
  `europe-southwest1`), `zone`, `cluster_name` (default `jenkins-2026`).
- `machine_type` (`e2-standard-8`), `node_count`/`min_node_count`/`max_node_count`,
  `disk_size_gb`.
- `enable_node_autoprovisioning` (+ `nap_max_cpu`/`nap_max_memory_gb`) — **do not
  set directly in CI**; it is exported as `TF_VAR_enable_node_autoprovisioning`
  from the single `config.yaml` flag so it can't desync from the ComputeClass wiring.
- `subnet_cidr`/`pods_cidr`/`services_cidr` (the VPC-native CIDR plan),
  `admin_emails` (IAP access + `container.clusterViewer`; set via
  `TF_VAR_admin_emails`, never committed).

## Key outputs

- `cluster_name`, `location`, `project_id`, `get_credentials_command`
  (the `gcloud container clusters get-credentials …` line), `endpoint`
  (sensitive). Consumed by the rest of the Day1 workflow (`get-credentials`,
  then `scripts/up.sh`).
