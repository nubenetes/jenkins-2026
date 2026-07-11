/*
 * Schema for the custom jenkins2026.* config keys (app-config.yaml). The
 * frontend visibility is what lets the EntityPage's CI/CD tab read the active
 * engine at runtime (app-backend injects runtime config into index.html).
 */
export interface Config {
  jenkins2026?: {
    /**
     * The platform's active CI engine (config.yaml ci.engine):
     * jenkins | tekton | githubactions | argoworkflows.
     * @visibility frontend
     */
    ciEngine?: string;
    /**
     * Public base domain (gateway.baseDomain) - used to build deep links to
     * the sibling IAP-protected UIs (Argo Workflows, Grafana, ...).
     * @visibility frontend
     */
    baseDomain?: string;
  };
}
