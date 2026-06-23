[← Previous: 301. Observability](./301-OBSERVABILITY.md) | [🏠 Home](../README.md) | [→ Next: 402. Pipelines as Code](./402-PIPELINES_AS_CODE.md)

---

# 401. Jenkins

## Accessing the UI & Admin Password

```bash
kubectl -n jenkins port-forward svc/jenkins 8080:8080
```

Open <http://localhost:8080>. If [Google login](#google-login-openid-connect) is configured, use the **Sign in with Google** button. Otherwise (or for break-glass/automation access), log in as `${JENKINS_ADMIN_ID}` (`jenkins.adminUser` in `config/config.yaml`, default `admin`) via the **escape hatch** — this login always works, regardless of OIDC. The password is randomly generated on first run by `scripts/01-namespaces.sh`. Retrieve it:

```bash
kubectl -n jenkins get secret jenkins-credentials -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

To rotate the password, delete the Secret and re-run `scripts/01-namespaces.sh` + `scripts/04-jenkins.sh` — a new random password is generated and printed once.

## Google Login (OpenID Connect)

Jenkins' security realm is [`oic-auth`](https://plugins.jenkins.io/oic-auth/) (`securityRealm.oic` in [`jenkins/casc/jcasc-base.yaml`](../jenkins/casc/jcasc-base.yaml)), so anyone can sign in with a Google account — Role-Based Authorization Strategy then decides what they can do. By default, a Google login only gets `authenticated-base` (read-only UI access); to grant the `admin` role to your own account, set `JENKINS_OIDC_ADMIN_EMAIL`.

Setting `JENKINS_OIDC_ADMIN_EMAIL` also dynamically configures administrator permissions for the corresponding user in ArgoCD's RBAC policy configmap (`argocd-rbac-cm`), ensuring unified admin privileges across both Jenkins and ArgoCD when logging in via Google OIDC.

1. **Create a third Google OAuth 2.0 Web application client** (can reuse the same GCP project as Headlamp and IAP clients, but must be its own client):
   - [Google Cloud Console](https://console.cloud.google.com/) → **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID** → Application type **Web application**.
   - **Authorized redirect URIs**: add `https://jenkins.<baseDomain>/securityRealm/finishLogin`. If you only access Jenkins via `kubectl port-forward`, also add `http://localhost:8080/securityRealm/finishLogin`.
   - Note the **Client ID** and **Client secret**.
   - On the **OAuth consent screen** (Audience tab), while the app is in **Testing**, add your Google account as a **Test user**.

2. **Add repository secrets** (your own email is **never committed to this repo**):

   ```bash
   gh secret set JENKINS_OIDC_CLIENT_ID     --body "<client ID from above>"
   gh secret set JENKINS_OIDC_CLIENT_SECRET --body "<client secret from above>"
   gh secret set JENKINS_OIDC_ADMIN_EMAIL   --body "you@gmail.com"
   ```

   Then re-run **Day2.redeploy.02 Redeploy Jenkins** (or **Day1.cluster.01 GKE provision**).

## Plugins & JCasC Fragments

[`helm/jenkins/values-common.yaml`](../helm/jenkins/values-common.yaml) tracks the latest Jenkins LTS (`controller.image.tag`) and pins **every** plugin — including transitive dependencies — to the exact version resolved against that core by `jenkins-plugin-cli`. This means a routine controller pod restart always installs the identical plugin set.

`scripts/04-jenkins.sh` installs the jenkinsci/helm-charts `jenkins` chart with three JCasC fragments passed via `--set-file`:

| File | Purpose |
|---|---|
| [`jcasc-base.yaml`](../jenkins/casc/jcasc-base.yaml) | Security realm (OIDC with Google, escape-hatch `admin` password), Role-Based Authorization Strategy, system message, **global pipeline library** `microservices-shared-library`, credentials (`container-registry`, `microservices-git`). |
| [`jcasc-otel.yaml`](../jenkins/casc/jcasc-otel.yaml) | Configures the `opentelemetry` plugin's global exporter — OTLP/gRPC to `otel-collector-gateway.observability.svc.cluster.local:4317`. |
| [`jcasc-seed-job.yaml`](../jenkins/casc/jcasc-seed-job.yaml) | Defines the main `seed-jobs` pipeline job that tracks `${JENKINS2026_REPO_BRANCH:-main}` to generate the stable pipelines. |

Beyond the kubernetes/git/JCasC/OTel plugins, three are aimed at UX:

- **[Pipeline Graph View](https://plugins.jenkins.io/pipeline-graph-view/)** — the maintained successor to Blue Ocean. Adds an interactive, pan/zoom stage graph to every build page.
- **[Dark Theme](https://plugins.jenkins.io/dark-theme/)** (+ Theme Manager) — native dark mode. `appearance.themeManager` defaults everyone to `darkSystem` (follows OS preference); each user can override from their *Appearance* tab.
- **[MCP Server](https://plugins.jenkins.io/mcp-server/)** — exposes Jenkins (jobs, builds, logs, SCM, replay) as an MCP server, so an MCP-capable client (Claude Code/Desktop, etc.) can query and drive this Jenkins directly. No JCasC config needed — it auto-registers its endpoints (`/mcp-server/sse`, `/mcp-server/mcp`, `/mcp-server/mcp-stateless`). Authenticate as `${JENKINS_ADMIN_ID}` with a personal **API token** (user profile → *Security* → *Add new Token*), passed as HTTP Basic Auth:
  ```
  claude mcp add --transport http jenkins <jenkins-url>/mcp-server/mcp \
    --header "Authorization: Basic <base64(user:token)>"
  ```

## Global Shared Library

Four steps used by every per-service pipeline: `microservicesBuild`, `microservicesImage`, `microservicesDeploy`, and `microservicesSmokeTest`. They handle everything from Maven/NPM builds to Helm deployments and OTel-instrumented smoke tests. A fifth step, `microservicesK6Smoke`, is used only by the `microservices-k6-smoke` job.

The library is stored at the repo root (`vars/`, `resources/`) — required by the `modernSCM` retriever so Jenkins can check out the library from the same repo as the pipeline.

See [402. Pipelines as Code](./402-PIPELINES_AS_CODE.md) for the pipeline stages and execution details.

## GitOps: why Jenkins is Helm-installed, and how it could move to ArgoCD

A common question, given the alternative [Tekton engine](./403-TEKTON.md) **is**
GitOps-managed by ArgoCD (an app-of-apps): why isn't Jenkins?

**It's a design choice, not a technical limitation.** The `jenkinsci/jenkins`
chart is an ordinary Helm chart and an ArgoCD `Application` (`source.chart: jenkins`,
`repoURL: https://charts.jenkins.io`) would deploy it. Today
[`scripts/04-jenkins.sh`](../scripts/04-jenkins.sh) installs it imperatively with
`helm upgrade --install` because the Jenkins install has several **apply-time,
runtime-computed inputs** that don't map cleanly onto "ArgoCD syncs what's in git":

- **Computed values overlay** — `04-jenkins.sh` generates a values file at run time (the Grafana base URL for the active `observability.mode`, `JENKINS_PUBLIC_URL`, a banner-links checksum used as a pod annotation to force a roll, …) and patches the `jenkins-credentials` Secret with computed links. ArgoCD syncs static git content, not values computed from cluster/env state.
- **Credential / token coupling** — [`scripts/08.5-argocd.sh`](../scripts/08.5-argocd.sh) mints an ArgoCD API token and stores it in `jenkins-credentials`; the pipeline reads it to run `argocd app sync`. That Jenkins↔ArgoCD chicken-and-egg is awkward to express in pure GitOps.
- **JCasC + secrets** — Jenkins config references secrets and computed URLs; GitOps-managing it means those must not live in git (so an external-secrets operator + sidecar wiring) rather than the current Secret patch.
- **Imperative rollback** — the script rolls the StatefulSet back on a failed upgrade.

Tekton, by contrast, is **stateless declarative manifests** with no
runtime-computed install inputs, so it drops straight into an ArgoCD app-of-apps
(see [403. Tekton → What gets installed](./403-TEKTON.md#what-gets-installed-gitops-via-argocd-app-of-apps)).

### How to move Jenkins to ArgoCD (if desired)

It's feasible; the migration would mirror the `platform-postgres` app-of-apps and
replace the four bullets above with GitOps-friendly equivalents:

1. **Parent `Application` → Helm chart** `argocd/jenkins/` (like `argocd/platform-postgres/`), with `{{repoUrl}}`/`{{branchStable}}` substituted at apply time, rendering a child `Application` that installs the upstream `jenkinsci/jenkins` chart (multi-source: chart + this repo's `helm/jenkins/values-*.yaml` via `$values`), pinned by `targetRevision`.
2. **Replace computed values with declarative inputs** — move the run-time-computed values (Grafana URL, public URL, banner links) into committed per-mode values files or a small ConfigMap the chart reads via `controller.containerEnvFrom`, so nothing is computed at apply time. Use an `argocd.argoproj.io/sync-wave` so it lands after ArgoCD itself.
3. **Secrets via External Secrets** — the platform already runs the External Secrets Operator ([`argocd/external-secrets-app.yaml`](../argocd/external-secrets-app.yaml)); model `jenkins-credentials` (admin password, registry/git creds, OIDC) as an `ExternalSecret` instead of an imperative `kubectl create secret`, so ArgoCD never owns raw secrets.
4. **Break the ArgoCD-token cycle** — provision the Jenkins ArgoCD account/token as part of `08.5-argocd.sh` (as it already does) and surface it to Jenkins via that same `ExternalSecret`, so the controller picks it up declaratively rather than via a Secret patch + pod restart.
5. **Let ArgoCD own rollout/health** — drop the imperative rollback; ArgoCD's sync + health checks (plus `selfHeal`) replace it.

The trade-off is **more moving parts for a stateful controller** (External Secrets
wiring, careful sync-waves, JCasC-as-external-secret) versus the current single
idempotent script. For a stable default engine that rarely changes, the script is
simpler; the GitOps version mainly pays off if you want Jenkins config drift to
auto-reconcile like the rest of the platform. This is **not implemented** — it's
the documented path if the project decides to make Jenkins fully GitOps-native.

---

[← Previous: 301. Observability](./301-OBSERVABILITY.md) | [🏠 Home](../README.md) | [→ Next: 402. Pipelines as Code](./402-PIPELINES_AS_CODE.md)

---

*401. Jenkins — jenkins-2026*
