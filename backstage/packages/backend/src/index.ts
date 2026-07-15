/*
 * jenkins-2026 Backstage backend (new backend system, Backstage 1.52.x).
 *
 * Deliberate omissions (docs/505 § Roadmap):
 *  - guest auth: production is always behind Google IAP; add
 *    @backstage/plugin-auth-backend-module-guest-provider locally only.
 *
 * Both CI-engine backends (jenkins) and the engine-independent argocd backend
 * are ALWAYS loaded - config decides what the frontend renders (the CI/CD tab
 * switches on jenkins2026.ciEngine at runtime).
 */
import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// core
backend.add(import('@backstage/plugin-app-backend'));
backend.add(import('@backstage/plugin-proxy-backend'));

// auth: Google IAP (JWT-verified) + the GitHub OAuth provider the GitHub
// Actions tab uses for its per-user API calls.
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-gcp-iap-provider'));
backend.add(import('@backstage/plugin-auth-backend-module-github-provider'));

// catalog (+ optional org-wide GitHub discovery - config-driven, idle without
// catalog.providers.github; the static locations in app-config.yaml are the
// primary source).
backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(import('@backstage/plugin-catalog-backend-module-github'));
backend.add(import('@backstage/plugin-catalog-backend-module-logs'));
// Teaches the CATALOG to validate `kind: Template`. Separate package from the
// scaffolder-backend below, and required even though that one is loaded: without it
// the catalog READS the template, then drops it with a warn-level
// "No processor recognized the entity ... possibly caused by a foreign kind" — the
// Create page just shows "No templates found" and nothing surfaces as an error.
// (allowing Template in catalog.rules is necessary but NOT sufficient.)
backend.add(
  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),
);

// permissions: allow-all - IAP already restricts WHO gets in; everyone who
// does is a platform admin (docs/505 § Credentials & RBAC).
backend.add(import('@backstage/plugin-permission-backend'));
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

// search, indexed in the same CNPG Postgres (pg engine).
backend.add(import('@backstage/plugin-search-backend'));
backend.add(import('@backstage/plugin-search-backend-module-pg'));
backend.add(import('@backstage/plugin-search-backend-module-catalog'));
backend.add(import('@backstage/plugin-search-backend-module-techdocs'));

// techdocs (builder local; mkdocs ships in the image).
backend.add(import('@backstage/plugin-techdocs-backend'));

// kubernetes: powers the Kubernetes tab AND the Tekton CI/CD tab (+ the Argo
// Workflows/Rollouts customResources views).
backend.add(import('@backstage/plugin-kubernetes-backend'));

// scaffolder: the "Onboard a service" golden path (docs/505 § Scaffolder). Its
// templates only ever open PULL REQUESTS against repos that already exist — no
// repo is ever created, so the platform's GITHUB_TOKEN needs no extra scope. The
// github module supplies publish:github:pull-request; the local module below
// supplies j2026:file:append, the one action the stock set lacks.
//
// The Roadmap's stated blocker for this ("drags the isolated-vm native toolchain
// (python3/g++) into the image") no longer holds and was re-verified before
// adding it: isolated-vm 6.x ships prebuilds/linux-x64, so `require`ing it works
// on node:24-trixie-slim with NO compiler — tested in that exact base image. The
// Dockerfile stays slim.
backend.add(import('@backstage/plugin-scaffolder-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-github'));
backend.add(import('./modules/scaffolderFileAppend'));

// CI/CD + GitOps integrations.
backend.add(import('@backstage-community/plugin-jenkins-backend'));
backend.add(import('@backstage-community/plugin-argocd-backend'));

// scorecard: entity-level KPIs (docs/505 § Scorecard tab). github ONLY for
// now - it rides the integrations.github token this app already configures
// for catalog ingestion, plus the github.com/project-slug annotation every
// entity already carries. Three other provider modules were evaluated and
// deliberately DEFERRED, not omitted by oversight (docs/505):
//  - openssf: verified LIVE against api.securityscorecards.dev before
//    adopting it - all three repos 404 (that public dataset only covers a
//    curated corpus of well-known OSS projects, not arbitrary forks like
//    these). Wiring it would ship a permanently-broken metric, not a
//    degrades-gracefully one; self-hosting scorecard results is a real
//    infra project, not "add a plugin".
//  - dependabot: needs the same per-repo "Dependabot alerts" GitHub setting
//    the Security tab's Dependabot card already found disabled - no value
//    wiring a second integration against data that isn't there yet.
//  - filecheck: keys off backstage.io/source-location, which for
//    gateway/jhipstersamplemicroservice currently resolves to THIS repo's
//    catalog file (they have no per-app catalog-info.yaml of their own)
//    rather than their GitHub forks - the same misattribution class the
//    SARIF-routing fix just closed elsewhere, unverified here.
backend.add(import('@red-hat-developer-hub/backstage-plugin-scorecard-backend'));
backend.add(
  import(
    '@red-hat-developer-hub/backstage-plugin-scorecard-backend-module-github'
  ),
);

backend.start();
