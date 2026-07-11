/*
 * The engine-aware CI/CD tab (docs/505 § CI-engine integration).
 *
 * Backstage plugins are COMPILE-TIME, so this one image ships all of them; the
 * platform's ACTIVE engine arrives at RUNTIME via the frontend-visible config
 * key jenkins2026.ciEngine (backstage-runtime-config ConfigMap -> app-config
 * env substitution -> injected into index.html by the app-backend). Switching
 * ci.engine therefore re-skins this tab with no rebuild.
 *
 * Argo Workflows has NO upstream Backstage plugin yet (community-plugins PR
 * #9192 in flight, verified 2026-07-11) - its case deep-links the IAP-protected
 * Argo Server UI and points at the entity's Kubernetes tab, where the
 * argoproj.io/v1alpha1 workflows customResource is surfaced.
 */
import React from 'react';
import { Typography } from '@material-ui/core';
import { useApi, configApiRef } from '@backstage/core-plugin-api';
import { EmptyState, InfoCard, Link } from '@backstage/core-components';
import { EntitySwitch } from '@backstage/plugin-catalog';
import {
  EntityJenkinsContent,
  isJenkinsAvailable,
} from '@backstage-community/plugin-jenkins';
import {
  EntityGithubActionsContent,
  isGithubActionsAvailable,
} from '@backstage-community/plugin-github-actions';
import { TektonCI, isTektonCIAvailable } from '@backstage-community/plugin-tekton';

const missingAnnotation = (annotation: string) => (
  <EmptyState
    title="Missing CI annotation"
    missing="field"
    description={`This entity is missing the '${annotation}' annotation for the active CI engine - add it in backstage/catalog/services.yaml.`}
  />
);

const ArgoWorkflowsContent = () => {
  const config = useApi(configApiRef);
  const baseDomain = config.getOptionalString('jenkins2026.baseDomain');
  const argoUrl = baseDomain
    ? `https://argo.${baseDomain}/workflows/argo-ci`
    : undefined;
  return (
    <InfoCard title="Argo Workflows (ci.engine=argoworkflows)">
      <Typography variant="body1" paragraph>
        There is no upstream Backstage plugin for Argo Workflows yet (the
        donation is in flight as backstage/community-plugins PR&nbsp;#9192 —
        this tab adopts it when it ships). Meanwhile:
      </Typography>
      <Typography variant="body1" paragraph>
        {argoUrl ? (
          <>
            • Open the{' '}
            <Link to={argoUrl}>Argo Workflows Server UI</Link> (IAP-protected,
            same Google identity as this portal) for runs, DAGs and logs.
          </>
        ) : (
          <>• The Argo Workflows Server UI link needs jenkins2026.baseDomain.</>
        )}
      </Typography>
      <Typography variant="body1">
        • The <b>Kubernetes</b> tab of this entity lists its{' '}
        <code>Workflow</code> custom resources live (argo-ci namespace).
      </Typography>
    </InfoCard>
  );
};

export const CicdContent = () => {
  const config = useApi(configApiRef);
  const engine =
    config.getOptionalString('jenkins2026.ciEngine') ?? 'jenkins';

  switch (engine) {
    case 'tekton':
      return (
        <EntitySwitch>
          <EntitySwitch.Case if={isTektonCIAvailable}>
            <TektonCI />
          </EntitySwitch.Case>
          <EntitySwitch.Case>
            {missingAnnotation('tekton.dev/cicd')}
          </EntitySwitch.Case>
        </EntitySwitch>
      );
    case 'githubactions':
      return (
        <EntitySwitch>
          <EntitySwitch.Case if={isGithubActionsAvailable}>
            <EntityGithubActionsContent />
          </EntitySwitch.Case>
          <EntitySwitch.Case>
            {missingAnnotation('github.com/project-slug')}
          </EntitySwitch.Case>
        </EntitySwitch>
      );
    case 'argoworkflows':
      return <ArgoWorkflowsContent />;
    case 'jenkins':
    default:
      return (
        <EntitySwitch>
          <EntitySwitch.Case if={isJenkinsAvailable}>
            <EntityJenkinsContent />
          </EntitySwitch.Case>
          <EntitySwitch.Case>
            {missingAnnotation('jenkins.io/job-full-name')}
          </EntitySwitch.Case>
        </EntitySwitch>
      );
  }
};
