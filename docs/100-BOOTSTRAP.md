[🏠 Home](../README.md) | [→ Next: 101. GitHub Actions Workflows](./101-GITHUB_ACTIONS_WORKFLOWS.md)

---

# 100. Bootstrap — the Root of Trust (Day0, "phase 0")

> **TL;DR** — Run this **once**, by hand, on your laptop, before anything else:
> ```bash
> ./scripts/bootstrap.sh up
> ```
> It asks who you are, creates the GCP foundation that lets GitHub Actions work,
> and sets the 4 repo secrets. To undo it (rarely): `./scripts/bootstrap.sh down`.

This page explains, from zero, **what the bootstrap is, why it is the only step you
run locally, and how to create and destroy it with one command.** If you have never
touched Terraform or GCP, you can still follow this — every command is copy‑paste.

## Table of contents
- [What "bootstrap" means here](#what-bootstrap-means-here)
- [Why it can't be a GitHub Actions workflow (the bootstrap paradox)](#why-it-cant-be-a-github-actions-workflow-the-bootstrap-paradox)
- [Where it sits in the lifecycle](#where-it-sits-in-the-lifecycle)
- [Prerequisites](#prerequisites)
- [Create the root: `bootstrap.sh up`](#create-the-root-bootstrapsh-up)
- [What it creates](#what-it-creates)
- [The state model (self-hosted in the bucket)](#the-state-model-self-hosted-in-the-bucket)
- [Destroy the root: `bootstrap.sh down`](#destroy-the-root-bootstrapsh-down)
- [FAQ & troubleshooting](#faq--troubleshooting)

---

## What "bootstrap" means here

Everything in this project is **Infrastructure as Code** run by **GitHub Actions**.
But GitHub Actions needs two things to exist *before* it can do anything in your
GCP project:

1. **A way to log in to GCP** — we use **Workload Identity Federation (WIF)**: a
   keyless trust that lets a GitHub workflow impersonate a GCP **service account**
   (no JSON keys ever stored). 
2. **A place to store Terraform state** — a **GCS bucket** (so two separate workflow
   runs — provision in the morning, destroy at night — share the same state).

The **bootstrap** is the one-time step that **creates those two things** (plus a
backups bucket). It is the *root of trust*: the seed that makes the whole automated
lifecycle possible.

```mermaid
flowchart LR
    you([You, a human<br/>with Owner on the project]) -->|run once, locally| BS["scripts/bootstrap.sh up"]
    BS --> WIF["WIF trust<br/>+ CI service account"]
    BS --> BUCKET[("GCS state bucket")]
    BS --> SECRETS["4 GitHub repo secrets"]
    BS --> DNS["Permanent public DNS zone<br/>(delegate once at parent domain)"]
    WIF & BUCKET & SECRETS & DNS --> GHA["GitHub Actions<br/>(Day0 / Day1 / Day2 / Decom)"]
    GHA -->|"authenticate via WIF,<br/>store state in the bucket"| GCP[("Your GCP project")]
    classDef seed fill:#ffd,stroke:#aa0,stroke-width:2px;
    class BS seed;
```

---

## Why it can't be a GitHub Actions workflow (the bootstrap paradox)

A natural question: *"everything else is a one-click workflow — why isn't the
bootstrap?"* Because it would have to use the very things it is creating:

```mermaid
flowchart TD
    A["A hypothetical<br/>'Day0 bootstrap' workflow in GitHub"] --> Q1{"Needs to authenticate<br/>to GCP…"}
    Q1 -->|"via WIF"| P1["…but WIF doesn't exist yet —<br/>the bootstrap creates it 🐔🥚"]
    A --> Q2{"Needs to store<br/>Terraform state…"}
    Q2 -->|"in the GCS bucket"| P2["…but the bucket doesn't exist yet —<br/>the bootstrap creates it 🐔🥚"]
    A --> Q3{"Needs permission to create<br/>WIF + IAM bindings…"}
    Q3 -->|"high privilege"| P3["…letting CI create its OWN trust is a<br/>privilege-escalation hole ⚠️"]
    classDef bad fill:#fdd,stroke:#c33;
    class P1,P2,P3 bad;
```

So there must always be **one manual seed**, done by a human with their own
credentials. That seed is `scripts/bootstrap.sh`. After it runs once, GitHub Actions
takes over and **everything else is remote and automated.**

| Concern | Bootstrap (this page) | Everything else (gke, grafana, azure, aws, gateway…) |
| :--- | :--- | :--- |
| Who runs it | **You, locally** (once) | **GitHub Actions** |
| Auth | your `gcloud` identity (Owner) | WIF (keyless) — *created by bootstrap* |
| Terraform state | local seed → **migrated into the bucket** | remote in the bucket — *created by bootstrap* |
| Frequency | once (idempotent; re-run to converge) | per session / on demand |

---

## Where it sits in the lifecycle

```mermaid
flowchart LR
    P0["phase 0 · ROOT<br/>scripts/bootstrap.sh up"]:::root --> D0["Day0 · persistent infra<br/>Gateway + backends"]
    D0 --> D1["Day1 · cluster<br/>(Day1.cluster.01 / .00)"]
    D1 --> D2["Day2 · ops<br/>redeploy / publish / traffic"]
    D2 --> DC["Decom · teardown<br/>(Decom.infra.00)"]
    DC -.->|"cluster + backends gone,<br/>root stays (cheap, reusable)"| D0
    DC ==>|"only if abandoning the project"| P9["phase 0 · ROOT teardown<br/>scripts/bootstrap.sh down"]:::root
    classDef root fill:#ffd,stroke:#aa0,stroke-width:2px;
```

The root is created **first** and destroyed **last** (if ever). A normal Decom leaves
the root in place — it costs almost nothing (two empty-ish buckets) and saves you
re-seeding every time.

---

## Prerequisites

| Tool | Why | Install |
| :--- | :--- | :--- |
| `gcloud` + `gsutil` | talk to GCP, set ADC | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| `terraform` (≥ 1.9) | create the resources | [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/downloads) |
| `gh` (GitHub CLI) | set the repo secrets | [cli.github.com](https://cli.github.com/) |

You also need:
- A **GCP project** with **billing enabled**.
- **Owner** (or `Editor` + `resourcemanager.projectIamAdmin`) on that project — the
  bootstrap creates IAM bindings + a WIF pool, which require admin rights.
- Push/admin access to the GitHub repo (to set its secrets).

The script checks each identity and **only prompts you to log in if you are not
already authenticated** — you don't pre-run any `gcloud auth` commands yourself.

---

## Create the root: `bootstrap.sh up`

```bash
./scripts/bootstrap.sh up
```

That's it. It will, in order:

```mermaid
sequenceDiagram
    autonumber
    participant U as You
    participant S as bootstrap.sh
    participant G as gcloud / gh
    participant T as Terraform
    participant C as GCP + GitHub
    U->>S: ./scripts/bootstrap.sh up
    S->>G: check gcloud user, ADC, gh — prompt login only if missing
    S->>U: ask GCP project ID (region/repo have defaults)
    S->>T: init + apply (LOCAL state) → create bucket + WIF + SA + DNS zone
    S->>T: write backend_override.tf → init -migrate-state → state now in the bucket
    S->>C: gh secret set ×4 (from Terraform outputs)
    S->>U: ✓ Root ready — GitHub Actions can now run
```

**Non-interactive** (CI-less automation or scripting): pass the inputs as env vars so
nothing is prompted:

```bash
PROJECT_ID=my-gcp-project \
REGION=us-central1 \
GITHUB_REPO=myorg/jenkins-2026 \
./scripts/bootstrap.sh up
```

It is **idempotent**: run it again any time to converge (e.g. after adding a role) —
on a second run it detects the remote state and just re-applies.

---

## What it creates

| Resource | Terraform | Purpose |
| :--- | :--- | :--- |
| **GCS state bucket** `<project>-jenkins-2026-tfstate` | `google_storage_bucket.tf_state` | remote Terraform state for **every** other module (versioned) |
| **CI service account** `jenkins-2026-ci@…` | `google_service_account.ci` | the identity GitHub Actions impersonates |
| **CI roles** | `google_project_iam_member.ci_roles` | what that SA may do (see [103](./103-GITHUB_SECRETS_INVENTORY.md#gcp_service_account)) |
| **WIF pool + provider** | `google_iam_workload_identity_pool*` | keyless GitHub→GCP trust |
| **WIF binding** | `google_service_account_iam_member.github_wif` | lets *this repo* impersonate the SA |
| **Postgres backups bucket** | `google_storage_bucket.postgres_backups` | survives cluster rebuilds |
| **Public DNS zone** `jenkins-2026-public-zone` | `google_dns_managed_zone.public` | the **permanent** delegated zone for `base_domain`; lives here so its nameservers never change. `Day0.infra.01`/`gateway-bootstrap` fills it with the wildcard-A + cert records. See [501 § Public access](./501-PLATFORM_OPERATIONS.md) |

> **One-time DNS delegation.** After `up`, run `terraform -chdir=terraform/bootstrap output dns_zone_name_servers` and create matching `NS` records for `base_domain` at your **parent domain's** DNS (e.g. Squarespace for `nubenetes.com`). Because the zone lives in this never-destroyed root tier, you do this **once for the life of the project** — every Decom/rebuild (even a gateway teardown) reuses it with no DNS changes.

…and then sets these **4 GitHub repo secrets** (the only ones the GCP workflows need):

| Secret | From Terraform output |
| :--- | :--- |
| `GCP_PROJECT_ID` | `project_id` |
| `TF_STATE_BUCKET` | `state_bucket` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `workload_identity_provider` |
| `GCP_SERVICE_ACCOUNT` | `ci_service_account_email` |

---

## The state model (self-hosted in the bucket)

Bootstrap is special: it **creates the very bucket** that stores remote state, so the
first apply *cannot* use it yet. The script handles this in two phases, so you end up
with **no fragile local `.tfstate`**:

```mermaid
flowchart LR
    subgraph Phase1["Phase 1 — first seed"]
      L["terraform apply<br/>(LOCAL state)"] --> B[("bucket created")]
    end
    subgraph Phase2["Phase 2 — self-host"]
      B --> M["write backend_override.tf<br/>terraform init -migrate-state"]
      M --> R[("state now lives IN the bucket<br/>prefix: jenkins-2026/bootstrap")]
    end
    Phase1 --> Phase2
```

After this, the bootstrap's own state is **remote** (in the same bucket as every other
module, just under a different prefix) — so any operator with GCP access can re-run it;
there is no precious local file to lose.

> The **only** irreducible local step is the *first* `apply` that creates the bucket —
> by physics it can't store its state in a bucket that doesn't exist yet.

---

## Destroy the root: `bootstrap.sh down`

> ⚠️ **Rarely needed.** A normal teardown (`Decom.infra.00`) leaves the root in place.
> Only destroy the root if you are **abandoning the project entirely**. It removes the
> WIF trust, the CI service account, **and the state bucket** — after which **no GitHub
> Actions workflow can touch GCP** until you run `up` again.

**Run it only after a full Decom** (clusters + all backends already destroyed):

```bash
./scripts/bootstrap.sh down
# type 'destroy-root' when prompted
```

```mermaid
sequenceDiagram
    autonumber
    participant U as You
    participant S as bootstrap.sh down
    participant T as Terraform
    U->>S: ./scripts/bootstrap.sh down
    S->>U: confirm ('destroy-root')
    S->>T: migrate state back to LOCAL (a bucket can't delete itself while holding its own state)
    S->>T: terraform destroy -var state_bucket_force_destroy=true (force-empties + deletes the bucket)
    S->>U: remove the 4 GitHub secrets
```

Why `state_bucket_force_destroy=true`? The bucket has `force_destroy = false` by
default (a safety so a normal apply can never nuke all your state). The teardown flips
it via a variable so `terraform destroy` can delete the bucket even though it still
holds other modules' (now-decommissioned) state objects + versioned copies.

To bring the project back later, run `./scripts/bootstrap.sh up` again (a fresh seed),
re-do the one-time `NS` delegation at your parent domain (the new zone gets new
nameservers — see the delegation note above), then run Day0 + Day1. (This re-delegation
is only needed after a **root** teardown like this; an ordinary `Decom.infra.00` leaves
the root — and the zone — in place, so no DNS step is needed to rebuild.)

---

## FAQ & troubleshooting

**"I thought all state was remote because of GitHub."** Correct for everything GitHub
Actions runs (state lives in the bucket). The bootstrap is the lone exception *at first
seed* — and the script immediately migrates even its own state into the bucket, so the
steady state is "all remote". See [the state model](#the-state-model-self-hosted-in-the-bucket).

**`terraform destroy` of the root fails: bucket "not empty".** Use `bootstrap.sh down`
(it passes `state_bucket_force_destroy=true`); a plain `terraform destroy` won't delete
a non-empty bucket because the default is `force_destroy = false`.

**403 on `certificatemanager.*delete` during a Gateway Decom.** Unrelated to the root,
but same family: the CI SA needs `roles/certificatemanager.owner` (editor lacks the
`.delete` permissions). It's granted by the bootstrap — re-run `./scripts/bootstrap.sh up`
to converge the role. See [902](./902-TROUBLESHOOTING.md).

**Lost the local state before migration finished.** If the first `apply` created the
bucket but the migrate step didn't run, re-run `./scripts/bootstrap.sh up`: it detects
the bucket and reconfigures against the remote state (importing any drift may be needed
in rare cases — `terraform import`).

**Is it safe to re-run `up`?** Yes — idempotent. It's the way to apply a bootstrap
change (e.g. a new IAM role) to the live project.

---

[🏠 Home](../README.md) | [→ Next: 101. GitHub Actions Workflows](./101-GITHUB_ACTIONS_WORKFLOWS.md)

---

*100. Bootstrap — the Root of Trust — jenkins-2026*
