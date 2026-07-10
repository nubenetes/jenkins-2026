# Documentation — jenkins-2026

> **This page is a reading map, not another guide.** GitHub renders it
> automatically when you browse [`docs/`](.). If you already know *which*
> document you want, the canonical index is the root
> [`README.md` § 1 Document Inventory](../README.md#1-document-inventory), or
> scan the [numbering scheme](#the-numbering-scheme) below. If you don't yet —
> because you just landed here — pick the
> [reading path](#reading-paths--start-here-depending-on-who-you-are) that
> matches who you are. Doc **authors** should read
> [Authoring conventions](#authoring-conventions-for-doc-authors) before adding
> or renaming a file.

The deep-dive documentation is **25 numbered guides** plus a small set of
**runbooks** (live, validated step-by-step procedures) and three **legacy
redirect stubs**. Every numbered guide is `NNN-TITLE.md`, carries prev/next
navigation, and is catalogued in the root
[`README.md` § 1 Document Inventory](../README.md#1-document-inventory) — that
table is the canonical index with a one-line description of each; this page adds
the two things the flat table can't: **the numbering scheme** (so a new doc
lands in the right band) and **role-based reading order** (so you don't start
with a 100 KB reference when you needed a 5-minute on-ramp).

---

## The numbering scheme

Documents are grouped into **hundreds bands**; the tens/units within a band are
assigned in the order the topics were added, not by importance. The band is the
part that carries meaning:

| Band | Category | What lives here |
| :--- | :--- | :--- |
| **1xx** | **Bootstrap & CI/CD lifecycle** | The Day0 root of trust ([100](./100-BOOTSTRAP.md)) and everything about the GitHub Actions lifecycle: the workflow inventory ([101](./101-GITHUB_ACTIONS_WORKFLOWS.md)), the WIF/automation architecture ([102](./102-GITHUB_ACTIONS_AUTOMATION.md)), the secrets/variables inventory ([103](./103-GITHUB_SECRETS_INVENTORY.md)), and the rebuild-safety model ([104](./104-REBUILD_SAFETY.md)) |
| **2xx** | **Architecture** | System architecture + the imperative-vs-GitOps split ([201](./201-ARCHITECTURE.md)) and the demo microservices app ([202](./202-MICROSERVICES-APP-ARCHITECTURE.md)) |
| **3xx** | **Observability & performance** | OTel components + the four obs backends ([301](./301-OBSERVABILITY.md)), the k6 traffic/load engine ([302](./302-K6_LOAD_TESTING.md)), and JVM tuning ([303](./303-JVM-TUNING.md)) |
| **4xx** | **CI engines** — one doc per engine | The four interchangeable `ci.engine` choices: Jenkins ([401](./401-JENKINS.md) UI/JCasC + [402](./402-PIPELINES_AS_CODE.md) pipelines-as-code + [406](./406-DECLARATIVE_VS_SCRIPTED.md) declarative-vs-scripted authoring), Tekton ([403](./403-TEKTON.md)), GitHub Actions / ARC ([404](./404-GITHUB_ACTIONS.md)), and Argo Workflows ([405](./405-ARGO_WORKFLOWS.md)) |
| **5xx** | **Platform ops & GitOps** | Platform operations — ArgoCD, Headlamp, Gateway/IAP, chaos/QA, progressive delivery ([501](./501-PLATFORM_OPERATIONS.md)); the microservices GitOps model ([502](./502-MICROSERVICES_GITOPS.md)); networking ([503](./503-NETWORKING.md)); opt-in backend TLS re-encryption ([504](./504-BACKEND_TLS.md)) |
| **6xx** | **Security & pinning** | DevSecOps scanning ([601](./601-DEVSECOPS.md)) and the version-pinning policy ([602](./602-VERSION_PINNING.md)) |
| **9xx** | **Reference** | Local development / quick start ([901](./901-LOCAL_DEVELOPMENT.md)), troubleshooting ([902](./902-TROUBLESHOOTING.md)), and the glossary ([903](./903-GLOSSARY.md)) |

**Why 9xx skips ahead:** the reference band is intentionally parked at the far
end so new mid-stack categories (a hypothetical 7xx/8xx) can be inserted without
renumbering the "start here" (1xx) and "look it up" (9xx) bookends.

**The 4xx band is the one to watch when adding an engine.** Every CI engine gets
its own doc so the four stay symmetric; the shared ~11-stage contract they all
implement (`patch-app-source.sh`, `services.yaml`, GHCR, GitOps push, OTel) is
described once per engine rather than in a shared doc. Jenkins is the default and
gets three docs (401 = the server/JCasC/MCP, 402 = its pipelines-as-code, 406 =
the Declarative-vs-Scripted authoring model that underpins its shared library)
because it predates the others and its Groovy authoring model has no analogue in
the YAML-based engines; Tekton/GitHub Actions/Argo Workflows get one each.

---

## Reading paths — start here depending on who you are

The flat inventory is a lookup table. These are ordered on-ramps. Several guides
open with a "newcomers → specialists" progression (a plain-terms summary or
`TL;DR`, then depth behind `<details>`), so you can stop at the first heading of
each once you have the shape.

### 🟢 Newcomer — "what *is* this?"

1. Root [`README.md`](../README.md) → the **"For newcomers — the platform in
   plain terms"** `<details>` block (build-and-ship factory, in plain language).
2. [202. Microservices App Architecture](./202-MICROSERVICES-APP-ARCHITECTURE.md) —
   *what* gets built and shipped (the JHipster gateway + Angular SPA + backend
   microservice), and *why* it's a fork of a production-shaped demo.
3. [201. Architecture](./201-ARCHITECTURE.md) — how the pieces fit: the
   imperative (push) vs GitOps (pull) split, namespaces, `config/config.yaml` as
   the single source of truth.

Then branch into whichever subsystem you need via the band table above. Keep
[903. Glossary](./903-GLOSSARY.md) open in a tab — it defines every recurring
acronym and repo term of art (WIF, NEG, PaC, seed job, `retire_ci_engine`, …)
once, so the dense guides read without reverse-engineering the vocabulary.

### 🔧 Operator — "stand the platform up"

1. [100. Bootstrap](./100-BOOTSTRAP.md) — the one-time, human-run root of trust
   (`bootstrap.sh up`). Nothing else works until this exists.
2. [101. GitHub Actions Workflows](./101-GITHUB_ACTIONS_WORKFLOWS.md) — the
   `DayN.tier.ZZ-resource` lifecycle; which workflow does what, in what order.
3. [102. GitHub Actions Automation](./102-GITHUB_ACTIONS_AUTOMATION.md) +
   [103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md) — the WIF/OIDC
   plumbing and the exact secrets/variables each workflow consumes.
4. [901. Local Development](./901-LOCAL_DEVELOPMENT.md) — the local equivalent
   (`up.sh` / `test/e2e.sh`) for a laptop run instead of CI.

Keep [104. Rebuild-Safety](./104-REBUILD_SAFETY.md) at hand: `Decom` + `Day1` is
a routine, repeated operation here, and 104 is why a rebuild converges instead of
colliding with leftover state.

### 🚨 SRE / on-call — "something is broken"

1. [902. Troubleshooting](./902-TROUBLESHOOTING.md) — the symptom → cause →
   fix catalogue (ArgoCD OIDC, Terraform/CI, Jenkins & GitOps push auth, CNPG WAL
   archive failures).
2. [104. Rebuild-Safety](./104-REBUILD_SAFETY.md) — if the failure only shows up
   *after* a teardown+rebuild, the collision-vs-residue bug class and the
   safe-by-design matrix explain it.
3. [runbooks/](./runbooks/) — the live, validated procedures (below). Reach for
   these when you need the exact commands, not the concept.

### 🏗️ Platform engineer / specialist — "own a subsystem"

Enter at the owning band and follow its cross-links:

- **CI engine work** → [402](./402-PIPELINES_AS_CODE.md) (the reference pipeline)
  then the engine you're on ([403](./403-TEKTON.md) / [404](./404-GITHUB_ACTIONS.md)
  / [405](./405-ARGO_WORKFLOWS.md)); all four share the contract in 402/404's
  stage-mapping tables.
- **Observability** → [301](./301-OBSERVABILITY.md) for signal correlation and
  the four backends, [302](./302-K6_LOAD_TESTING.md) for the load engine,
  [303](./303-JVM-TUNING.md) for JVM-side performance.
- **GitOps / delivery** → [501](./501-PLATFORM_OPERATIONS.md) (ArgoCD, Rollouts,
  Gateway/IAP) and [502](./502-MICROSERVICES_GITOPS.md) (Helm-vs-Kustomize,
  decommission ordering, CNPG HA).
- **Networking** → [503](./503-NETWORKING.md).
- **Security** → [601](./601-DEVSECOPS.md) (scanning) and
  [602](./602-VERSION_PINNING.md) (pinning policy).

### 🔒 Security reviewer — "what's the threat surface?"

1. [601. DevSecOps](./601-DEVSECOPS.md) — the SAST/IaC/image scanning gates
   (Semgrep, CodeQL, Trivy) in the pipeline.
2. [503. Networking](./503-NETWORKING.md) — NetworkPolicy segmentation,
   Dataplane V2 enforcement, WireGuard inter-node encryption, north-south
   ingress/egress and the defense-in-depth model.
3. [103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md) +
   [100. Bootstrap](./100-BOOTSTRAP.md) — the keyless WIF/OIDC trust model and
   where the (very few) long-lived credentials live.
4. [201. Architecture § namespaces & in-cluster secrets](./201-ARCHITECTURE.md)
   and [602. Version Pinning](./602-VERSION_PINNING.md) — the supply-chain
   pinning posture.

---

## Runbooks — validated live procedures

[`docs/runbooks/`](./runbooks/) holds **step-by-step operational procedures that
were run against a real cluster and captured verbatim** — the *how do I actually
do this* companion to the *what/why* of the numbered guides. They are deliberately
**not numbered** and **carry no prev/next nav chain**: they're leaf procedures,
linked *from* the numbered doc whose subsystem they exercise, not woven into the
100→903 reading order.

| Runbook | Companion doc(s) |
| :--- | :--- |
| [Log Correlation Validation](./runbooks/log-correlation-validation.md) — validate logs ↔ metrics ↔ traces end-to-end (enable DEBUG, restart pods, generate traffic, verify in Grafana) | [301. Observability](./301-OBSERVABILITY.md) |
| [NAP → Spot CI nodes](./runbooks/nap-spot-provisioning.md) — validate GKE Node Auto-Provisioning + the `ci-spot` ComputeClass provision Spot, scale-to-zero build nodes, and read the `SSD_TOTAL_GB` ceiling | [201. Architecture](./201-ARCHITECTURE.md), [501. Platform Operations](./501-PLATFORM_OPERATIONS.md) |
| [CNPG Restore from Backup](./runbooks/cnpg-restore-from-backup.md) — recover a microservices Postgres database from the barman GCS backups (base backup + WAL / PITR): when to restore vs when a rebuild is meant to start empty, the `bootstrap.recovery` manifest, PITR target selection, and the `Expected empty archive` cutover gotcha | [502. Microservices GitOps](./502-MICROSERVICES_GITOPS.md), [902. Troubleshooting](./902-TROUBLESHOOTING.md) |

**Rule of thumb:** if it's *conceptual* (why the platform is shaped this way, a
matrix, a design decision), it's a numbered guide; if it's a *sequence of live
commands you'd run to prove or repair something*, it's a runbook.

---

## Legacy redirect stubs

Three pre-consolidation filenames survive as one-line redirects so old links and
bookmarks don't 404. Don't add content to them — edit the target instead:

- [`architecture.md`](./architecture.md) → [201. Architecture](./201-ARCHITECTURE.md)
- [`observability.md`](./observability.md) → [301. Observability](./301-OBSERVABILITY.md)
- [`pipelines-as-code.md`](./pipelines-as-code.md) → [401. Jenkins](./401-JENKINS.md) + [402. Pipelines as Code](./402-PIPELINES_AS_CODE.md)

---

## Authoring conventions (for doc authors)

<details>
<summary>Everything you must do to add, rename, or move a numbered doc</summary>

### Naming & placement

- **Filename is `NNN-TITLE.md`** — a three-digit code in the correct
  [hundreds band](#the-numbering-scheme) + an `UPPER_SNAKE` or `Hyphenated` title
  (match the existing files in the band). The number is permanent: other docs,
  the root README, and CLAUDE.md link to it by name.
- Pick the **next free tens/units in the band** (e.g. a fifth architecture doc is
  `203-…`). Assign in *insertion* order — the band, not the low digits, carries
  meaning.

### The prev/next navigation chain

Every numbered doc opens and closes with the **same** nav line, and the whole set
forms one linked chain `100 → 101 → … → 902`. The format (copy from an adjacent
doc):

```
[← Previous: 103. Secrets Inventory](./103-GITHUB_SECRETS_INVENTORY.md) | [🏠 Home](../README.md) | [→ Next: 201. Architecture](./201-ARCHITECTURE.md)
```

- The **first** doc (100) omits `← Previous`; the **last** (903) omits `→ Next`.
- The line appears **twice**: once at the very top (above the `# NNN. Title`
  heading, followed by a `---`) and once at the very bottom.
- The footer additionally ends with an italic signature line:
  `*NNN. Title — jenkins-2026*`.
- **Inserting a doc mid-chain means editing its two neighbours' nav lines** so
  the `← Previous` / `→ Next` links point through the new file. Runbooks and
  legacy stubs are *not* in this chain.

### The three places to register a new doc

Adding a numbered guide is not done until all three are updated (grep the root
README to confirm):

1. **Root [`README.md` § 1 Document Inventory](../README.md#1-document-inventory)** —
   add a table row (code · category · linked title · one-line description).
2. **Root `README.md` per-doc ToC block** — the `**[NNN · Title](./docs/…)**`
   entry with its sub-heading anchors (the block starting near
   [`README.md` line 234](../README.md)).
3. **The `docs — N guides` badge** ([`README.md` line 12](../README.md)) — bump
   the count to the number of numbered `docs/NNN-*.md` guides.

Update **this page's** [band table](#the-numbering-scheme) and, if the doc opens a
new subsystem, the relevant [reading path](#reading-paths--start-here-depending-on-who-you-are).

### Renaming a heading other docs anchor to

Headings become anchors (`## Foo Bar` → `#foo-bar`). Before renaming one, **grep
both this repo and `jenkins-2026-gitops-config` for links to the old anchor** and
update them — the root README's per-doc ToC block is the most common linker.

### Voice & house style

- Dense and precise; lead with a `TL;DR`/plain-terms on-ramp, push depth behind
  `<details>`, keep the newcomer able to stop at the first heading.
- Cross-link by `[NNN. Title](./NNN-…​.md)`, never by bare filename in prose.
- No secret material in examples — ship `*.example.yaml` /
  `terraform.tfvars.example` and keep the real files gitignored.

</details>

---

[🏠 Home](../README.md) | [→ Start the chain: 100. Bootstrap](./100-BOOTSTRAP.md)

---

*Documentation index — jenkins-2026*
