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

---

[← Previous: 301. Observability](./301-OBSERVABILITY.md) | [🏠 Home](../README.md) | [→ Next: 402. Pipelines as Code](./402-PIPELINES_AS_CODE.md)

---

*401. Jenkins — jenkins-2026*
