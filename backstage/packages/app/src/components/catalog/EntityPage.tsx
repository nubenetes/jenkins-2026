/*
 * Entity pages for the jenkins-2026 catalog (create-app template shape, minus
 * scaffolder/catalog-import, plus: the runtime-switched CI/CD tab
 * (../cicd/CicdContent), the ArgoCD deployment views, the Kubernetes tab and
 * the TechDocs Mermaid addon).
 */
import React from 'react';
import { Grid } from '@material-ui/core';
import {
  EntityApiDefinitionCard,
  EntityConsumedApisCard,
  EntityConsumingComponentsCard,
  EntityHasApisCard,
  EntityProvidedApisCard,
  EntityProvidingComponentsCard,
} from '@backstage/plugin-api-docs';
import {
  EntityAboutCard,
  EntityDependsOnComponentsCard,
  EntityDependsOnResourcesCard,
  EntityHasComponentsCard,
  EntityHasResourcesCard,
  EntityHasSubcomponentsCard,
  EntityHasSystemsCard,
  EntityLayout,
  EntityLinksCard,
  EntitySwitch,
  EntityOrphanWarning,
  EntityProcessingErrorsPanel,
  EntityRelationWarning,
  isComponentType,
  isKind,
  isOrphan,
  hasCatalogProcessingErrors,
  hasRelationWarnings,
} from '@backstage/plugin-catalog';
import {
  EntityUserProfileCard,
  EntityGroupProfileCard,
  EntityMembersListCard,
  EntityOwnershipCard,
} from '@backstage/plugin-org';
import { EntityTechdocsContent } from '@backstage/plugin-techdocs';
import { EntityKubernetesContent } from '@backstage/plugin-kubernetes';
import {
  Direction,
  EntityCatalogGraphCard,
} from '@backstage/plugin-catalog-graph';
import { TechDocsAddons } from '@backstage/plugin-techdocs-react';
import { Mermaid } from 'backstage-plugin-techdocs-addon-mermaid';
import { J2026DocsStyles } from '../techdocs/J2026DocsStyles';
import {
  ArgocdDeploymentSummary,
  ArgocdDeploymentLifecycle,
  isArgocdConfigured,
} from '@backstage-community/plugin-argocd';
import {
  RELATION_API_CONSUMED_BY,
  RELATION_API_PROVIDED_BY,
  RELATION_CONSUMES_API,
  RELATION_DEPENDENCY_OF,
  RELATION_DEPENDS_ON,
  RELATION_HAS_PART,
  RELATION_PART_OF,
  RELATION_PROVIDES_API,
} from '@backstage/catalog-model';
import { CicdContent } from '../cicd/CicdContent';
import { ObservabilityContent } from '../observability/ObservabilityContent';
import { SecurityContent } from '../security/SecurityContent';
import {
  EntityGrafanaDashboardsCard,
  EntityGrafanaAlertsCard,
  isDashboardSelectorAvailable,
  isAlertSelectorAvailable,
} from '@backstage-community/plugin-grafana';
import { isSecurityInsightsAvailable } from '@roadiehq/backstage-plugin-security-insights';
import { EntityJenkinsContent } from '@backstage-community/plugin-jenkins';
import { EntityGithubActionsContent } from '@backstage-community/plugin-github-actions';
import { TektonCI } from '@backstage-community/plugin-tekton';

/* The Monitoring tab only appears on entities that opted in via the grafana
 * annotations - keeps Group/User/Location pages noise-free. */
const hasGrafanaAnnotations = (e: Parameters<typeof isAlertSelectorAvailable>[0]) =>
  Boolean(isDashboardSelectorAvailable(e)) || isAlertSelectorAvailable(e);

const cicdContent = (
  <CicdContent>
    <EntityJenkinsContent />
    <EntityGithubActionsContent />
    <TektonCI />
  </CicdContent>
);

/* Same static-tree trick as cicdContent, but here it is the API factory that
 * needs it: grafanaPlugin registers its default apiRef (plugin.grafana.service)
 * only when Backstage's element-tree traversal discovers a grafanaPlugin
 * extension in the JSX. Referenced only inside ObservabilityContent's render
 * body the plugin is never found and the cards crash with NotImplementedError
 * on mount. Rendering is still exclusively the runtime obsMode switch inside. */
const monitoringContent = (
  <ObservabilityContent>
    <EntityGrafanaDashboardsCard />
    <EntityGrafanaAlertsCard />
  </ObservabilityContent>
);

const entityWarningContent = (
  <>
    <EntitySwitch>
      <EntitySwitch.Case if={isOrphan}>
        <Grid item xs={12}>
          <EntityOrphanWarning />
        </Grid>
      </EntitySwitch.Case>
    </EntitySwitch>
    <EntitySwitch>
      <EntitySwitch.Case if={hasRelationWarnings}>
        <Grid item xs={12}>
          <EntityRelationWarning />
        </Grid>
      </EntitySwitch.Case>
    </EntitySwitch>
    <EntitySwitch>
      <EntitySwitch.Case if={hasCatalogProcessingErrors}>
        <Grid item xs={12}>
          <EntityProcessingErrorsPanel />
        </Grid>
      </EntitySwitch.Case>
    </EntitySwitch>
  </>
);

const overviewContent = (
  <Grid container spacing={3} alignItems="stretch">
    {entityWarningContent}
    <Grid item md={6}>
      <EntityAboutCard />
    </Grid>
    <Grid item md={6} xs={12}>
      <EntityCatalogGraphCard height={400} />
    </Grid>
    {/* GitOps state at a glance (engine-independent - ArgoCD deploys the
        microservices whatever CI engine built them). */}
    <EntitySwitch>
      <EntitySwitch.Case if={e => Boolean(isArgocdConfigured(e))}>
        <Grid item md={12}>
          <ArgocdDeploymentSummary />
        </Grid>
      </EntitySwitch.Case>
    </EntitySwitch>
    <Grid item md={4} xs={12}>
      <EntityLinksCard />
    </Grid>
    <Grid item md={8} xs={12}>
      <EntityHasSubcomponentsCard />
    </Grid>
  </Grid>
);

const techdocsContent = (
  <EntityTechdocsContent>
    <TechDocsAddons>
      <Mermaid />
      <J2026DocsStyles />
    </TechDocsAddons>
  </EntityTechdocsContent>
);

const serviceEntityPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      {overviewContent}
    </EntityLayout.Route>

    {/* The active engine's pipeline view - Jenkins / GitHub Actions / Tekton /
        Argo Workflows, switched at runtime on jenkins2026.ciEngine. */}
    <EntityLayout.Route path="/ci-cd" title="CI/CD">
      {cicdContent}
    </EntityLayout.Route>

    <EntityLayout.Route
      path="/deployments"
      title="Deployments"
      if={e => Boolean(isArgocdConfigured(e))}
    >
      <ArgocdDeploymentLifecycle />
    </EntityLayout.Route>

    <EntityLayout.Route path="/kubernetes" title="Kubernetes">
      <EntityKubernetesContent refreshIntervalMs={30000} />
    </EntityLayout.Route>

    {/* Grafana dashboards/alerts, switched at runtime on jenkins2026.obsMode
        (live cards for oss/grafana-cloud, deep-link card for managed-*). */}
    <EntityLayout.Route
      path="/monitoring"
      title="Monitoring"
      if={hasGrafanaAnnotations}
    >
      {monitoringContent}
    </EntityLayout.Route>

    {/* GitHub Code Scanning (Semgrep + CodeQL) + Dependabot alerts - reuses
        the github.com/project-slug annotation the CI/CD tab's GitHub Actions
        case already depends on (docs/601 § SARIF upload). */}
    <EntityLayout.Route
      path="/security"
      title="Security"
      if={isSecurityInsightsAvailable}
    >
      <SecurityContent />
    </EntityLayout.Route>

    <EntityLayout.Route path="/api" title="API">
      <Grid container spacing={3} alignItems="stretch">
        <Grid item md={6}>
          <EntityProvidedApisCard />
        </Grid>
        <Grid item md={6}>
          <EntityConsumedApisCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>

    <EntityLayout.Route path="/dependencies" title="Dependencies">
      <Grid container spacing={3} alignItems="stretch">
        <Grid item md={6}>
          <EntityDependsOnComponentsCard />
        </Grid>
        <Grid item md={6}>
          <EntityDependsOnResourcesCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>

    <EntityLayout.Route path="/docs" title="Docs">
      {techdocsContent}
    </EntityLayout.Route>
  </EntityLayout>
);

const websiteEntityPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      {overviewContent}
    </EntityLayout.Route>
    <EntityLayout.Route path="/ci-cd" title="CI/CD">
      {cicdContent}
    </EntityLayout.Route>
    <EntityLayout.Route path="/kubernetes" title="Kubernetes">
      <EntityKubernetesContent refreshIntervalMs={30000} />
    </EntityLayout.Route>
    <EntityLayout.Route
      path="/monitoring"
      title="Monitoring"
      if={hasGrafanaAnnotations}
    >
      {monitoringContent}
    </EntityLayout.Route>
    <EntityLayout.Route
      path="/security"
      title="Security"
      if={isSecurityInsightsAvailable}
    >
      <SecurityContent />
    </EntityLayout.Route>
    <EntityLayout.Route path="/docs" title="Docs">
      {techdocsContent}
    </EntityLayout.Route>
  </EntityLayout>
);

const defaultEntityPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      {overviewContent}
    </EntityLayout.Route>
    {/* jenkins-2026-infra (type infrastructure) lands here - the platform
        dashboards (NAP, gateway, collector, ...) are exactly its content. */}
    <EntityLayout.Route
      path="/monitoring"
      title="Monitoring"
      if={hasGrafanaAnnotations}
    >
      {monitoringContent}
    </EntityLayout.Route>
    <EntityLayout.Route
      path="/security"
      title="Security"
      if={isSecurityInsightsAvailable}
    >
      <SecurityContent />
    </EntityLayout.Route>
    <EntityLayout.Route path="/docs" title="Docs">
      {techdocsContent}
    </EntityLayout.Route>
  </EntityLayout>
);

const componentPage = (
  <EntitySwitch>
    <EntitySwitch.Case if={isComponentType('service')}>
      {serviceEntityPage}
    </EntitySwitch.Case>
    <EntitySwitch.Case if={isComponentType('website')}>
      {websiteEntityPage}
    </EntitySwitch.Case>
    {/* the infra Component (type infrastructure) gets the k8s-less default */}
    <EntitySwitch.Case>{defaultEntityPage}</EntitySwitch.Case>
  </EntitySwitch>
);

const apiPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3}>
        {entityWarningContent}
        <Grid item md={6}>
          <EntityAboutCard />
        </Grid>
        <Grid item md={6} xs={12}>
          <EntityCatalogGraphCard height={400} />
        </Grid>
        <Grid container item md={12}>
          <Grid item md={6}>
            <EntityProvidingComponentsCard />
          </Grid>
          <Grid item md={6}>
            <EntityConsumingComponentsCard />
          </Grid>
        </Grid>
      </Grid>
    </EntityLayout.Route>
    <EntityLayout.Route path="/definition" title="Definition">
      <Grid container spacing={3}>
        <Grid item xs={12}>
          <EntityApiDefinitionCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);

const userPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3}>
        {entityWarningContent}
        <Grid item xs={12} md={6}>
          <EntityUserProfileCard />
        </Grid>
        <Grid item xs={12} md={6}>
          <EntityOwnershipCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);

const groupPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3}>
        {entityWarningContent}
        <Grid item xs={12} md={6}>
          <EntityGroupProfileCard />
        </Grid>
        <Grid item xs={12} md={6}>
          <EntityOwnershipCard />
        </Grid>
        <Grid item xs={12}>
          <EntityMembersListCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);

const systemPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3} alignItems="stretch">
        {entityWarningContent}
        <Grid item md={6}>
          <EntityAboutCard />
        </Grid>
        <Grid item md={6} xs={12}>
          <EntityCatalogGraphCard height={400} />
        </Grid>
        <Grid item md={4} xs={12}>
          <EntityLinksCard />
        </Grid>
        <Grid item md={8}>
          <EntityHasComponentsCard />
        </Grid>
        <Grid item md={6}>
          <EntityHasApisCard variant="gridItem" />
        </Grid>
        <Grid item md={6}>
          <EntityHasResourcesCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>
    <EntityLayout.Route path="/diagram" title="Diagram">
      <EntityCatalogGraphCard
        direction={Direction.TOP_BOTTOM}
        title="System Diagram"
        height={700}
        relations={[
          RELATION_PART_OF,
          RELATION_HAS_PART,
          RELATION_API_CONSUMED_BY,
          RELATION_API_PROVIDED_BY,
          RELATION_CONSUMES_API,
          RELATION_PROVIDES_API,
          RELATION_DEPENDENCY_OF,
          RELATION_DEPENDS_ON,
        ]}
        unidirectional={false}
      />
    </EntityLayout.Route>
  </EntityLayout>
);

const domainPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3} alignItems="stretch">
        {entityWarningContent}
        <Grid item md={6}>
          <EntityAboutCard />
        </Grid>
        <Grid item md={6} xs={12}>
          <EntityCatalogGraphCard height={400} />
        </Grid>
        <Grid item md={6}>
          <EntityHasSystemsCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);

export const entityPage = (
  <EntitySwitch>
    <EntitySwitch.Case if={isKind('component')} children={componentPage} />
    <EntitySwitch.Case if={isKind('api')} children={apiPage} />
    <EntitySwitch.Case if={isKind('group')} children={groupPage} />
    <EntitySwitch.Case if={isKind('user')} children={userPage} />
    <EntitySwitch.Case if={isKind('system')} children={systemPage} />
    <EntitySwitch.Case if={isKind('domain')} children={domainPage} />
    <EntitySwitch.Case>{defaultEntityPage}</EntitySwitch.Case>
  </EntitySwitch>
);
