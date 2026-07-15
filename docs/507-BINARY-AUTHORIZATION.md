[← Previous: 506. Service Mesh](./506-SERVICE-MESH.md) | [🏠 Home](../README.md) | [→ Next: 601. DevSecOps](./601-DEVSECOPS.md)

---

# 507. Binary Authorization — supply-chain admission control (opt-in)

**TL;DR** — Setting **`security.binaryAuthorization.enabled: true`** (override
`JENKINS2026_BINARY_AUTHORIZATION_ENABLED`) and re-running `Day1` makes the GKE
cluster **only admit container images that carry a cryptographic attestation
signed by this project's attestor** — i.e. images that actually went through
*this* platform's pipeline and its [DevSecOps scan gates](./601-DEVSECOPS.md).
It **closes the loop** that scanning alone leaves open: Semgrep/CodeQL/Trivy can
*flag* a bad image, but nothing stops an *unscanned* or *rogue* image from being
deployed — Binary Authorization is the admission controller that enforces
provenance. **Orthogonal** to [backend TLS](./504-BACKEND_TLS.md) /
[the service mesh](./506-SERVICE-MESH.md) (it governs *which images run*, not
*how pods talk*) — it composes with any of them. Default **`false`**; default
enforcement **`dryrun`** (log, don't block) so it's safe to switch on in a PoC.

## Understanding Binary Authorization (newcomers → specialists)

Binary Authorization is a **deploy-time bouncer**: it sits at the Kubernetes
admission door and only lets a Pod run if its image carries a **cryptographic
attestation** — a KMS-signed statement *"this exact image digest was built and vetted
by us"*. Nothing signs itself: the **pipeline** signs each image after it passes the
scan gates, and the **cluster policy** refuses (or merely logs) anything unsigned.
Read this once and the rest of the page is just "which object holds which half of the
trust".

<details>
<summary>🧠 Mental model — Binary Authorization (mindmap)</summary>

```mermaid
mindmap
  root((Binary Authorization))
    Signing
      Cloud KMS asymmetric key
      only the CI identity may sign
      signs the image DIGEST
    Attestation
      signed claim over a digest
      anchored on a Container Analysis note
    Attestor
      trusts the KMS public key
      the policy trusts the attestor
    Policy
      project singleton
      require attestation
      allowlist GKE system images
    Enforcement
      dryrun logs violations
      enforce blocks the Pod
    Admission
      GKE checks at Pod create
      cluster consults the policy
    Pipeline
      sign-and-attest single source
      all four CI engines
```

</details>

**Reading it —** the seven branches split the trust in half: the **signing** side (a
Cloud KMS key only the pipeline can use, signing image *digests*) produces
**attestations**, anchored on a Container Analysis **note**; an **attestor** binds the
KMS public key so the **policy** can say "require an attestation from this attestor";
at **admission** the cluster checks every Pod's image against that policy and either
**enforces** (block) or runs in **dryrun** (log); and the **pipeline** is what
actually signs, from one shared script across all four engines.

<details>
<summary>🟢 For newcomers — the mental model in 6 objects</summary>

| Object | What it is | Analogy |
|---|---|---|
| **Cloud KMS key** | An asymmetric signing key whose *private* half never leaves KMS; only the CI identity may use it | The pipeline's tamper-proof rubber stamp |
| **Attestation** | A signature over an image **digest** (`sha256:…`), never a mutable tag | A wax seal on *this exact* build |
| **Container Analysis note** | The anchor an attestation attaches to | The ledger the seals are recorded in |
| **Attestor** | Binds the KMS *public* key + the note; the policy trusts the attestor | The notary whose seal the door recognises |
| **Policy** | The project-wide rule: "require an attestation from our attestor" (+ allowlist GKE images) | The bouncer's guest list |
| **Admission** | The moment GKE checks a Pod's image against the policy on `create` | The bouncer at the door |

So the loop is: *the pipeline builds + scans an image → signs its digest with the KMS
key → an attestation lands on the note → at deploy, GKE admission checks the image
against the policy → attested ⇒ runs; unattested ⇒ blocked (`enforce`) or logged
(`dryrun`).*
</details>

<details>
<summary>🔴 For specialists — the moving parts and how they're wired here</summary>

- **The project singleton policy.** [`terraform/gke/security.tf`](../terraform/gke/security.tf)
  provisions a `google_binary_authorization_policy` whose `default_admission_rule` is
  `evaluation_mode: REQUIRE_ATTESTATION` + `require_attestations_by: [attestor]`, with
  `admission_whitelist_patterns` for the GKE-managed images (`gke.gcr.io/*`,
  `registry.k8s.io/*`, …) so kube-system can always schedule. The cluster opts in via
  `binary_authorization { evaluation_mode = PROJECT_SINGLETON_POLICY_ENFORCE }`.
- **`enforce` vs `dryrun` is the policy's `enforcement_mode`.**
  `ENFORCED_BLOCK_AND_AUDIT_LOG` vs `DRYRUN_AUDIT_LOG_ONLY`, driven by
  `TF_VAR_binary_authorization_enforce` (from `security.binaryAuthorization.enforcementMode`).
  Default `dryrun` — safe on a PoC.
- **The attestor's trust anchor is a KMS PKIX key.**
  `google_binary_authorization_attestor` references the Container Analysis note + the
  KMS crypto-key version's PEM (`data.google_kms_crypto_key_version`). Signing uses
  `gcloud … binauthz attestations sign-and-create --keyversion=…` — no PGP.
- **Keyless signer identity.** A dedicated `jenkins-2026-binauthz-signer` GSA holds
  `cloudkms.signerVerifier` (on the key) + Container-Analysis + attestor-viewer roles;
  each CI engine's build KSA impersonates it via Workload Identity (`binauthz_signer_ksas`).
- **Single-source signing.** [`resources/sign-and-attest-image.sh`](../resources/sign-and-attest-image.sh)
  is called by all four engines after the push (like `patch-app-source.sh`); it
  resolves the immutable digest and no-ops unless `BINAUTHZ_ENABLED=true`.
</details>

## The flag

| Key | Default | Override | Consumers |
|---|---|---|---|
| `security.binaryAuthorization.enabled` | `false` | `JENKINS2026_BINARY_AUTHORIZATION_ENABLED` | [`terraform/gke`](../terraform/gke) (`TF_VAR_binary_authorization_enabled` → API enablement + KMS key + attestor + cluster policy + cluster `enable_binary_authorization`) · [`resources/sign-and-attest-image.sh`](../resources/sign-and-attest-image.sh) (called by all four CI engines) |
| `security.binaryAuthorization.enforcementMode` | `dryrun` | — | `TF_VAR_binary_authorization_enforce` → the cluster policy's `evaluationMode`/`enforcementMode` (`dryrun` = `DRYRUN_AUDIT_LOG_ONLY`, `enforce` = `ENFORCED_BLOCK_AND_AUDIT_LOG`) |

Consumers gate on
[`j2026_binary_authorization_active`](../scripts/lib/common.sh). Unlike the mesh
/ backend TLS there is no CRD to probe — Binary Authorization is a GKE cluster
property + a project policy, both set by `terraform/gke` from the same flag — so
the gate is simply the resolved flag, kept as a function only to make every
consumer read one uniform predicate.

## What it closes — the gap in the DevSecOps loop

The platform already **builds, scans, and pushes** images across
[four CI engines](./README.md) ([601](./601-DEVSECOPS.md): Semgrep SAST, CodeQL,
Trivy image/IaC), then deploys via GitOps. The missing link is **admission**:

<details>
<summary>🔀 The scan → sign → admit pipeline (flowchart)</summary>

```mermaid
flowchart LR
    build["build image<br/>(4 engines)"] --> scan["scan gates<br/>Semgrep · CodeQL · Trivy"]
    scan --> sign["sign + attest DIGEST<br/>resources/sign-and-attest-image.sh"]
    sign --> push["push to GHCR"]
    push --> deploy["GitOps deploy"]
    deploy --> admit{"Binary Authorization<br/>admission webhook"}
    admit -->|"attestation valid"| run["Pod runs ✅"]
    admit -->|"no/invalid attestation"| block["dryrun → log · enforce → REJECT"]
```

</details>

Without Binary Authorization the `admit` diamond doesn't exist — any image that
reaches the cluster runs. With it, only an image whose **digest** was signed by
the project's attestor (a Cloud KMS key that *only the pipeline* can use) is
admitted. That is the difference between "we scan our images" and "the cluster
*cannot run* an image that wasn't scanned and signed by us".

## How it works

| Piece | Role |
|---|---|
| **Cloud KMS asymmetric signing key** (`jenkins-2026-binauthz` keyring / `jenkins-2026-attestor-key`) | The private half signs attestations; the public half is embedded in the attestor. Only the CI service account (Workload Identity) may sign — no key material leaves KMS. |
| **Container Analysis note** (`jenkins-2026-attestor-note`) | The anchor an attestation attaches to. |
| **Attestor** (`jenkins-2026-attestor`) | Binds the note + the KMS public key. The cluster policy trusts *this* attestor. |
| **Cluster Binary Authorization policy** | `defaultAdmissionRule` requires an attestation from the attestor; GKE system images + (optionally) the platform's own registries are allow-listed; `evaluationMode` = dryrun/enforce from the flag. Attached to the cluster via `enable_binary_authorization`. |
| [`resources/sign-and-attest-image.sh`](../resources/sign-and-attest-image.sh) | **Single source**, called by all four engines (like [`resources/patch-app-source.sh`](../resources/patch-app-source.sh)): after the image is pushed, resolves its **digest** and runs `gcloud beta container binauthz attestations sign-and-create` with the KMS key. Signs the *digest*, never a mutable tag. |

All Terraform resources are `count`-gated on
`var.binary_authorization_enabled`, so `false` is a complete no-op.

How those objects chain into trust — signing on the left, verification on the right:

<details>
<summary>🔀 The trust chain — KMS key → attestor → policy → cluster (object model)</summary>

```mermaid
flowchart LR
  subgraph signing["Signing — pipeline, per image"]
    key[["Cloud KMS key<br/>private half stays in KMS"]]
    key -->|"signs the digest"| att["Attestation<br/>signed claim over sha256"]
  end
  att -->|"attached to"| note["Container Analysis<br/>Note"]

  subgraph anchor["Trust anchor"]
    attestor["Attestor"] -->|"references"| note
    attestor -->|"embeds"| pub["KMS PUBLIC key (PKIX)"]
  end
  key -.->|"public half"| pub

  policy["Project Policy<br/>require attestation"] -->|"trusts"| attestor
  cluster["GKE cluster<br/>PROJECT_SINGLETON_POLICY_ENFORCE"] -->|"consults at admission"| policy

  classDef sign fill:#eef,stroke:#66c;
  classDef verify fill:#e6ffe6,stroke:#2a2;
  class key,att,note sign
  class attestor,pub,policy,cluster verify
```

</details>

**Reading it —** trust flows **left-to-right when signing, right-to-left when
verifying**: the pipeline uses the **KMS private key** to sign an image **digest** →
an **attestation** attached to the **note**; the **attestor** binds that note + the
KMS **public** key; the **policy** trusts the attestor ("require an attestation from
it"); and the **cluster** consults the policy at **every Pod admission**. Break any
link — no signature, wrong key, missing note, or a policy that doesn't trust the
attestor — and the image counts as unattested: **blocked** under `enforce`, **logged**
under `dryrun`.

## Pipeline wiring — how each engine signs

All four CI engines call the ONE signing script `resources/sign-and-attest-image.sh`
right after the image push (the single-source pattern, like
[`patch-app-source.sh`](../resources/patch-app-source.sh)). The step is **safe by
default**: the script checks `BINAUTHZ_ENABLED` **first** and no-ops (exit 0)
unless it is `true`, so an inactive cluster runs the step as a harmless no-op.

| Engine | Call site | Signing context |
|---|---|---|
| **Jenkins** | [`vars/microservicesImage.groovy`](../vars/microservicesImage.groovy) (after push) | a `gcloud` container appended to the agent pod **only when the flag is on** ([`vars/MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy)); script materialised via `libraryResource` |
| **Tekton** | [`tekton/tasks/build-push-image.yaml`](../tekton/tasks/build-push-image.yaml) `sign-attest` step | `google/cloud-sdk:slim` step |
| **Argo Workflows** | [`argoworkflows/templates/microservices-wftmpl.yaml`](../argoworkflows/templates/microservices-wftmpl.yaml) `build-sign` template | `google/cloud-sdk:slim` template |
| **GitHub Actions** | [`jenkins/pipelines/seed/microservices-ci.yml.tmpl`](../jenkins/pipelines/seed/microservices-ci.yml.tmpl) sign step | on the ARC runner (needs gcloud present) |

### The three enablement hooks (beyond the shared script)

Calling the script is only half the wiring — three more hooks flip it from a no-op
into a real signature. Because **Jenkins is the repo's default/active engine**, its
three hooks are **implemented and live-validatable**; the other three engines carry
the same call-site + env scaffold, their **Workload-Identity binding is already
granted** (all four KSAs are in `binauthz_signer_ksas`), and the one remaining
per-engine flip is documented so it lands the moment that engine becomes active.

| Hook | What it does | Jenkins (active) | Tekton / Argo | GitHub Actions |
|---|---|---|---|---|
| **1 — thread the flag** | put `BINAUTHZ_ENABLED=true` in the build env only when the flag is on | ✅ `04-jenkins.sh` patches `binauthz-enabled` into `jenkins-credentials` → `containerEnv` ([`values-common.yaml`](../helm/jenkins/values-common.yaml)) → JCasC `globalNodeProperties` ([`jcasc-base.yaml`](../jenkins/casc/jcasc-base.yaml)) → `env.BINAUTHZ_ENABLED` on the agent | env scaffold present (`value: "false"`); flip via the ArgoCD-managed task/template param when that engine is active | render-time `sed` in `06-githubactions-pipelines.sh` (same mechanism as the other `{{…}}` placeholders) |
| **2 — bind + annotate the KSA** | let the build pod impersonate the signer GSA via Workload Identity | ✅ GSA binding via `binauthz_signer_ksas` **+** the `iam.gke.io/gcp-service-account` annotation auto-threaded as a chart **helm-parameter** by `04-jenkins.sh` (the jenkins KSA is ArgoCD-managed, so a raw `kubectl annotate` would drift) | ✅ binding granted; annotate `tekton-ci/tekton-ci` · `argo-ci/argoworkflows-ci` when active | ✅ binding granted; annotate `arc-runners/arc-runner-scale-set` when active |
| **3 — gcloud present** | the signing call needs the `gcloud` CLI | ✅ flag-gated `gcloud` container on the agent pod ([`MicroservicesPipeline.groovy`](../vars/MicroservicesPipeline.groovy)) | ✅ `google/cloud-sdk:slim` step image | add a `setup-gcloud` step on the ARC runner |

The Workload-Identity **bindings** are granted up-front by `terraform/gke` —
`binauthz_signer_ksas` lists all four engines' build KSAs, and an unused engine's
binding is inert, so this is safe. The KSA-side **annotation** is the only
engine-specific piece: auto-applied for Jenkins, and applied for the other engines
when that engine is the active one (confirm the live KSA name first — ARC in
particular generates its runner SA name).

**Net on the default Jenkins engine:** flip `security.binaryAuthorization.enabled=true`
and re-run `Day1` — all three hooks wire with no manual step, the signature appears on
the next build, and `enforce` mode then admits only images this pipeline signed. Until
the flag is on, the signing step is a **safe no-op** on every engine.

<details>
<summary>📄 Configuration reference — the policy, attestor, and signing call</summary>

**Cluster opt-in** — consult the project policy at admission (`terraform/gke`):
```hcl
binary_authorization {
  evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
}
```

**Project policy** — require an attestation, allowlist GKE system images ([`terraform/gke/security.tf`](../terraform/gke/security.tf)):
```hcl
resource "google_binary_authorization_policy" "this" {
  admission_whitelist_patterns { name_pattern = "gke.gcr.io/*" }
  admission_whitelist_patterns { name_pattern = "registry.k8s.io/*" }
  default_admission_rule {
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = var.binary_authorization_enforce ? "ENFORCED_BLOCK_AND_AUDIT_LOG" : "DRYRUN_AUDIT_LOG_ONLY"
    require_attestations_by = [google_binary_authorization_attestor.this[0].name]
  }
  global_policy_evaluation_mode = "ENABLE"
}
```

**The signing call** — after the push, in the pipeline (all four engines, via the single-source script):
```bash
# resources/sign-and-attest-image.sh <image-ref>   (no-ops unless BINAUTHZ_ENABLED=true)
gcloud beta container binauthz attestations sign-and-create \
  --project="$PROJECT_ID" \
  --artifact-url="$REGISTRY/$SERVICE@sha256:<digest>" \
  --attestor="jenkins-2026-attestor" --attestor-project="$PROJECT_ID" \
  --keyversion="projects/$PROJECT_ID/locations/<loc>/keyRings/jenkins-2026-binauthz/cryptoKeys/jenkins-2026-attestor-key/cryptoKeyVersions/1"
```

**See a denial (`enforce` mode)** — an unsigned image is rejected at admission:
```bash
kubectl run rogue --image=ghcr.io/nubenetes/jenkins-2026-microservices/gateway:unsigned -n microservices
# Error ... admission webhook "imagepolicywebhook.image-policy.k8s.io" denied the request:
#   Image ... denied by Binary Authorization: No attestations found for attestor jenkins-2026-attestor
```

</details>

## `dryrun` vs `enforce`

| | `dryrun` (default) | `enforce` |
|---|---|---|
| Policy mode | `DRYRUN_AUDIT_LOG_ONLY` | `ENFORCED_BLOCK_AND_AUDIT_LOG` |
| Unattested image | **runs**, violation logged to Cloud Audit Logs | **rejected** at admission |
| Use | See what *would* block without wedging a deploy — the right first step on a PoC | The real zero-trust posture |
| Failure blast radius | none (informational) | a broken signing step **blocks every new Pod** — flip to `enforce` only once the sign+attest step is proven green across all engines |

Start `dryrun`, read the audit logs, then flip to `enforce`.

## It composes with everything (orthogonal)

Binary Authorization is on a **different axis** than the intra-cluster TLS axis
([506](./506-SERVICE-MESH.md)) — it never touches how pods talk, only which
images run. So unlike backend-TLS↔CSM, it is **not** mutually exclusive with
anything:

| | backend TLS | CSM mesh | Binary Authorization |
|---|---|---|---|
| Governs | LB→pod TLS | east-west + LB→pod mTLS | **which images admit** |
| Axis | intra-cluster TLS (pick one) | intra-cluster TLS (pick one) | **supply chain (independent)** |
| Combine? | ✅ with BinAuth | ✅ with BinAuth | ✅ with either TLS choice |

In the GHA forms it is therefore a **separate boolean input**, not part of the
single `intra_cluster_tls` dropdown.

## Why Binary Authorization (and why not "just scan")

| Approach | What it stops | Gap |
|---|---|---|
| **Scan only** (today, [601](./601-DEVSECOPS.md)) | Flags known-bad images *in the pipeline* | Nothing enforces that only scanned/signed images *run* — bypass the pipeline, or push straight to the namespace, and it deploys |
| **Admission webhook (custom / OPA Gatekeeper)** | Arbitrary policy | You build + operate the webhook + its signing story yourself |
| **Binary Authorization** (this doc) | **Only attested images run**, enforced by GKE natively | Requires a KMS key + attestor + a signing step in the pipeline — all provisioned here |

Binary Authorization is the **GKE-native** way to enforce provenance without
running your own admission controller, and its **basic enforcement is free on
GKE** (see Cost). Note: the *advanced* continuous-validation / GKE Security
Posture premium tier is a paid add-on — this feature uses only the **free basic
enforcement**.

## Cost

Effectively **free for a PoC**: basic Binary Authorization enforcement carries
**no GKE surcharge**; a Cloud KMS asymmetric key is ~$0.06/key-version/month plus
fractions of a cent per signing operation; Container Analysis attestation storage
is negligible. Unlike [CSM](./506-SERVICE-MESH.md#the-cost-model--per-client-not-per-vcpu),
there is no per-client/per-vCPU meter here.

## Rebuild-safety

The **cluster policy** and the `enable_binary_authorization` cluster property are
Terraform-managed and die/recreate with the cluster (safe-by-construction). The
**KMS keyring/key, the attestor, and the Container Analysis note** are
**persistent, fixed-identity** GCP resources → the [104](./104-REBUILD_SAFETY.md)
rebuild-safety class. Two options, both valid:

- **Ephemeral** (simplest for a PoC): `count`-gated, destroyed on `Decom` and
  recreated on `Day1`. Old attestations (signed by the previous key) become
  invalid — fine, because a rebuild rebuilds and re-signs the images anyway.
  **But "destroyed" is a lie for KMS, and that bit us live** ([run 29433092250](https://github.com/nubenetes/jenkins-2026/actions/runs/29433092250)): a KMS **keyring can never be deleted** and a **key only enters a scheduled-destruction window** — so `terraform destroy` removes them from *state* while they **linger in GCP**, and the next `Day1`'s create then **409s** (`KeyRing … already exists`). Stable names + no `prevent_destroy` are necessary but **not sufficient**: the crypto-key re-adopts its scheduled-destroyed version by name, but the keyring create still collides. The Day1 workflow closes it with an **"Adopt lingering KMS keyring/key"** step that `terraform import`s the survivors into state **only when they already exist** (an `import {}` block can't — it fails `plan` on a truly-fresh project where the keyring doesn't exist yet). The `google_gke_hub_membership` (mesh) has a sibling create-time hazard — the Fleet API rejects it while the cluster is mid-operation (`Error code 9`) — fixed by depending on the node pool + a create timeout so Terraform waits for the cluster to go idle.
- **Persistent** (if you want attestations to survive rebuilds): keep the KMS
  key + attestor out of the per-cluster tier (a bootstrap-tier module, like the
  DNS zone in [`terraform/bootstrap`](../terraform/bootstrap)) so their identity
  is stable — *tombstone-adoption* / *keep-if-present* per the 104 matrix.

⚠️ **KMS keys cannot be truly hard-deleted immediately** (they enter a scheduled
destruction window). A `Decom`+`Day1` re-creating a keyring/key of the *same
name* must therefore tolerate an existing (soft-deleted or present) key — the
canonical 104 "persistent external resource with a fixed identity collides with a
fresh rebuild" hazard. The ephemeral path handles this by `count`-gating and
using create-if-absent semantics.

## Lifecycle

- **Enable**: set `security.binaryAuthorization.enabled=true` (durable, per-run
  env, or the `binary_authorization` workflow input) and **re-run `Day1`**. Keep
  `enforcementMode=dryrun` until the sign+attest step is proven green across the
  active engine.
- **Promote to enforce**: set `enforcementMode=enforce`, re-run `Day1`.
- **Disable**: set `enabled=false`, re-run `Day1` — the cluster policy reverts to
  `ALWAYS_ALLOW`, the pipeline signing step no-ops.
- **Teardown**: `terraform destroy` (Decom) removes the policy, attestor, note,
  and (ephemeral path) the KMS key.

## Verifying it

```bash
gcloud container binauthz policy export --project "$PROJECT"          # the cluster policy + evaluationMode
gcloud container binauthz attestors list --project "$PROJECT"         # jenkins-2026-attestor present
gcloud container binauthz attestations list \
  --attestor jenkins-2026-attestor --project "$PROJECT"               # attestations for pushed digests
kubectl get pod -A -o json | jq -r '.items[].spec.containers[].image' # running images (all should be attested under enforce)
# dryrun: violations appear in Cloud Audit Logs (protoPayload.metadata for binaryauthorization.googleapis.com)
```

Under `enforce`, a deliberately-unsigned image should be **rejected** at Pod
creation with a Binary Authorization denial; under `dryrun` it runs and the
denial is only logged.

---

[← Previous: 506. Service Mesh](./506-SERVICE-MESH.md) | [🏠 Home](../README.md) | [→ Next: 601. DevSecOps](./601-DEVSECOPS.md)

---

*507. Binary Authorization — supply-chain admission control — jenkins-2026*
