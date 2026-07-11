/*
 * jenkins-2026 Backstage backend (new backend system, Backstage 1.52.x).
 *
 * Deliberate omissions (docs/505 § Roadmap):
 *  - scaffolder: no golden-path templates yet, and dropping it keeps the
 *    isolated-vm native toolchain (python3/g++) out of the image.
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

// CI/CD + GitOps integrations.
backend.add(import('@backstage-community/plugin-jenkins-backend'));
backend.add(import('@backstage-community/plugin-argocd-backend'));

backend.start();
