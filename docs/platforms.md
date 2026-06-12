# Platform Support

`platform.target` in [`config/config.yaml`](../config/config.yaml) (default
`gke`), overridable per-run via the `JENKINS2026_PLATFORM` environment
variable, selects **one** of four overlays. Every script reads this via
`scripts/lib/config.sh` (`J2026_PLATFORM`); only one platform is active per
cluster/run.

```bash
# default (config.yaml: platform.target: gke)
./scripts/up.sh

# override for this run only
JENKINS2026_PLATFORM=openshift ./scripts/up.sh
```

All four overlays assume an **existing** cluster reachable via the current
`kubectl` context - this repo provisions no infrastructure (no VPCs, node
pools, IAM, etc).

## GKE (default)

- `helm/jenkins/values-gke.yaml`: `persistence.storageClass: standard-rwo`.
  Ingress disabled by default (no DNS record assumed); flip
  `controller.ingress.enabled` and set `hostName` to expose Jenkins via the
  GCE ingress controller (`ingressClassName: gce`).
- `helm/petclinic/values-stable.yaml`/`values-develop.yaml`:
  `global.platform: gke` -> `petclinic.ingressClassName` helper resolves to
  `gce` if `ingress.enabled: true`.
- Standard, unprivileged pod security context
  (`runAsNonRoot: true` + `seccompProfile: RuntimeDefault` on PetClinic pods;
  Jenkins controller `runAsUser/Group: 1000`, `fsGroup: 1000`).

## EKS

- `helm/jenkins/values-eks.yaml`: `persistence.storageClass: gp3`. Ingress
  overlay documents the AWS Load Balancer Controller (`ingressClassName:
  alb`, `alb.ingress.kubernetes.io/scheme: internet-facing`,
  `target-type: ip`) - install the [AWS Load Balancer
  Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
  separately if you enable it.
- Same pod security model as GKE.

## AKS

- `helm/jenkins/values-aks.yaml`: `persistence.storageClass: managed-csi`.
  Ingress overlay uses AKS's built-in **App Routing** add-on
  (`ingressClassName: webapprouting.kubernetes.azure.com`) - enable it on the
  cluster (`az aks approuting enable`) if you turn ingress on.
- Same pod security model as GKE.

## OpenShift 4.20+

- `helm/jenkins/values-openshift.yaml`: blanks out
  `containerSecurityContext`/`podSecurityContextOverride` (the
  `restricted-v2` SCC assigns UID/GID/`fsGroup` from the namespace's
  allocated range and **rejects** pods that hard-code values outside it);
  `persistence.storageClass: ""` (cluster default CSI - e.g. ODF/Ceph RBD or
  the managed cloud's CSI driver on ROSA/ARO); `controller.ingress.enabled:
  false`.
- **Routes instead of Ingress**: `scripts/04-jenkins.sh` applies
  [`helm/jenkins/openshift/route.yaml`](../helm/jenkins/openshift/route.yaml)
  (edge TLS, `Redirect` policy) for the Jenkins UI;
  [`helm/petclinic/templates/route.yaml`](../helm/petclinic/templates/route.yaml)
  (gated by `global.platform == "openshift"`) does the same for
  `petclinic-angular` when `ingress.enabled: true`. Both let the cluster's
  default router assign a hostname under `*.apps.<cluster-domain>` - no DNS
  record needed.
- `helm/petclinic/templates/deployment.yaml` omits `runAsNonRoot`/
  `seccompProfile` on OpenShift (the SCC sets these) and the
  [Angular Dockerfile](../resources/angular/Dockerfile) runs nginx on
  unprivileged port **8080** as UID 101 with `chgrp -R 0`/`chmod -R g=u`
  (arbitrary-UID compatible).
- **Known manual step - `docker:dind` build agent**: the `docker` container
  in [`Jenkinsfile.petclinic`](../jenkins/pipelines/Jenkinsfile.petclinic)
  runs `docker:26-dind` with `securityContext.privileged: true`, which the
  default `restricted-v2` SCC does not allow. On OpenShift, either:
  - grant the `jenkins` ServiceAccount the `privileged` SCC:
    `oc adm policy add-scc-to-user privileged -z jenkins -n jenkins`
    (acceptable for a PoC; broadens that ServiceAccount's capabilities
    cluster-wide), or
  - replace the `docker`/`maven`/build steps with a rootless builder
    (`buildah`/`kaniko`) - out of scope for this PoC but noted here for a
    production follow-up.

## Observability mode vs. platform

`observability.mode` (`grafana-cloud` default | `oss` | `managed`) is
**independent** of `platform.target` - any platform can use any
observability mode. See [`observability.md`](observability.md) for the
`grafana-cloud`/`oss` details.

### `managed` (stub)

For managed Grafana offerings (Amazon Managed Grafana + AMP, Azure Managed
Grafana, Google Cloud Managed Service for Prometheus + self-hosted
Grafana, etc.), set `observability.mode: managed` -
`scripts/03-observability.sh` and `scripts/07-grafana-dashboards.sh` then
exit immediately without creating resources. To wire this PoC up to such a
stack:

1. Find that service's OTLP ingestion endpoint and auth model.
2. Populate the `grafana-cloud-credentials` Secret (same shape as
   [`observability/otel-collector/secret.example.yaml`](../observability/otel-collector/secret.example.yaml))
   with that endpoint/credentials.
3. Either reuse `values-grafana-cloud.yaml`/`values-grafana-cloud-logs.yaml`
   as-is if the target accepts the same `otlphttp` + Basic-auth shape, or
   copy them and adjust the `exporters:` block for the target's
   authentication extension (e.g. `sigv4auth` for AMP).
4. Import `observability/grafana/dashboards/*.json` into that Grafana
   instance manually, or adapt `07-grafana-dashboards.sh`'s API call to its
   dashboard API.
