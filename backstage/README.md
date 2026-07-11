# jenkins-2026 Backstage app

The custom [Backstage](https://backstage.io) app behind the platform's
developer portal (`https://backstage.<baseDomain>`, IAP-protected). Full
design + operations guide: [docs/505-BACKSTAGE.md](../docs/505-BACKSTAGE.md).

- **Pinned to Backstage 1.52.1** (the release manifest pins in
  `package.json` / `backstage.json`; verified 2026-07-11 — see docs/602).
- **One image, four CI engines**: the Jenkins / GitHub Actions / Tekton
  (+ Kubernetes/ArgoCD) plugins are all compiled in; the active engine's CI/CD
  tab is picked at **runtime** from `jenkins2026.ciEngine` (the
  `backstage-runtime-config` ConfigMap written by `scripts/08.95-backstage.sh`).
  Argo Workflows has no upstream plugin yet (community-plugins PR #9192) — its
  tab deep-links the IAP-protected Argo UI and the Kubernetes tab shows the
  `Workflow` CRs.
- **Sign-in = Google IAP** (`gcpIap` provider, JWT-verified; no second login).
- **No scaffolder / no guest auth** in the image, deliberately (no templates
  yet; avoids the isolated-vm native toolchain; IAP always fronts prod).

## Build & publish (the one-time bootstrap)

The image is built by **`Day2.publish.06-backstage`** (host build: Node 24 +
yarn 4.8.1 → `yarn build:backend` → `packages/backend/Dockerfile`) and pushed
to `ghcr.io/nubenetes/jenkins-2026-backstage:<branch>` + `:sha-<sha>`. Run it
once per branch before the first `backstage.enabled` Day1 — the image persists
across cluster rebuilds.

## Local development

```bash
cd backstage
corepack enable
yarn install                       # generates yarn.lock (not committed yet)
cp app-config.local.example.yaml app-config.local.yaml   # then edit
yarn dev                           # app on :3000, backend on :7007
```

Local dev needs a Postgres and the guest auth module — see the notes inside
`app-config.local.example.yaml`.
