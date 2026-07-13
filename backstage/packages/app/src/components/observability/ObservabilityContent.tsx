/*
 * The mode-aware Monitoring tab (docs/505 § Grafana integration).
 *
 * Same runtime-switch pattern as ../cicd/CicdContent: this ONE image ships the
 * Grafana plugin; the platform's observability.mode arrives at RUNTIME via the
 * frontend-visible config key jenkins2026.obsMode (backstage-runtime-config
 * ConfigMap -> app-config env substitution), so switching modes re-skins this
 * tab with no rebuild.
 *
 * Live Grafana cards render ONLY for oss and grafana-cloud - the two modes
 * whose Grafana accepts a static service-account Bearer token, which is the
 * only credential shape the plugin can send (a fixed Authorization header on
 * the '/grafana/api' proxy endpoint). managed-azure / managed-aws get a
 * deep-link InfoCard instead: Azure Managed Grafana authenticates with
 * short-lived Entra ID tokens and Amazon Managed Grafana with AWS
 * IAM/SigV4-derived sessions - credentials that expire in minutes/hours and
 * cannot be a static proxy header. Wiring them anyway would be a silent
 * time-bomb (the tab dies when the first token expires) - the same
 * credential-model mismatch that retired the managed LLM-app backends
 * (docs/301). Full decision record: docs/505-BACKSTAGE.md
 * § "Why the managed modes are deferred".
 */
import React from 'react';
import { Grid, Typography } from '@material-ui/core';
import { useApi, configApiRef } from '@backstage/core-plugin-api';
import { EmptyState, InfoCard, Link } from '@backstage/core-components';
import { EntitySwitch } from '@backstage/plugin-catalog';
import {
  EntityGrafanaDashboardsCard,
  EntityGrafanaAlertsCard,
  isDashboardSelectorAvailable,
  isAlertSelectorAvailable,
} from '@backstage-community/plugin-grafana';

const missingAnnotation = () => (
  <EmptyState
    title="Missing Grafana annotations"
    missing="field"
    description="This entity has neither 'grafana/dashboard-selector' nor 'grafana/alert-label-selector' - add them in backstage/catalog/ to surface its dashboards and alert rules."
  />
);

/* managed-azure / managed-aws: deep link only (see the header comment). */
const ManagedGrafanaContent = ({ mode }: { mode: string }) => {
  const config = useApi(configApiRef);
  // grafana.domain is frontend-visible (the plugin builds its own links from
  // it); for the managed modes 08.95-backstage.sh sets it to the managed
  // workspace endpoint when known, or the literal 'unset' when not.
  const domain = config.getOptionalString('grafana.domain');
  const grafanaUrl = domain && domain !== 'unset' ? domain : undefined;
  const vendor =
    mode === 'managed-azure' ? 'Azure Managed Grafana' : 'Amazon Managed Grafana';
  return (
    <InfoCard title={`${vendor} (observability.mode=${mode})`}>
      <Typography variant="body1" paragraph>
        Live in-portal dashboards/alerts cards are deliberately not wired for
        the managed modes: {vendor} authenticates with short-lived
        {mode === 'managed-azure' ? ' Entra ID' : ' AWS IAM/SigV4'} tokens,
        while the Backstage Grafana plugin can only send a static
        service-account Bearer token - a credential the managed workspaces do
        not issue. See docs/505-BACKSTAGE.md § "Why the managed modes are
        deferred" for the decision record.
      </Typography>
      <Typography variant="body1">
        {grafanaUrl ? (
          <>
            • Open the <Link to={grafanaUrl}>{vendor} workspace</Link> directly
            (cloud-provider sign-in) for this platform's dashboards and alerts.
          </>
        ) : (
          <>
            • Open your {vendor} workspace from the cloud console - the
            endpoint was not resolvable when this portal was deployed.
          </>
        )}
      </Typography>
    </InfoCard>
  );
};

export const ObservabilityContent = () => {
  const config = useApi(configApiRef);
  const mode = config.getOptionalString('jenkins2026.obsMode');

  switch (mode) {
    case 'oss':
    case 'grafana-cloud':
      return (
        <EntitySwitch>
          <EntitySwitch.Case
            if={e =>
              Boolean(isDashboardSelectorAvailable(e)) ||
              isAlertSelectorAvailable(e)
            }
          >
            <Grid container spacing={3} alignItems="stretch">
              <EntitySwitch>
                <EntitySwitch.Case
                  if={e => Boolean(isDashboardSelectorAvailable(e))}
                >
                  <Grid item md={6} xs={12}>
                    <EntityGrafanaDashboardsCard />
                  </Grid>
                </EntitySwitch.Case>
              </EntitySwitch>
              <EntitySwitch>
                <EntitySwitch.Case if={isAlertSelectorAvailable}>
                  <Grid item md={6} xs={12}>
                    <EntityGrafanaAlertsCard />
                  </Grid>
                </EntitySwitch.Case>
              </EntitySwitch>
            </Grid>
          </EntitySwitch.Case>
          <EntitySwitch.Case>{missingAnnotation()}</EntitySwitch.Case>
        </EntitySwitch>
      );
    case 'managed-azure':
    case 'managed-aws':
      return <ManagedGrafanaContent mode={mode} />;
    default:
      // Runtime config lacks jenkins2026.obsMode (image newer than the
      // backstage-runtime-config ConfigMap) - degrade loudly, not blankly.
      return (
        <EmptyState
          title="Observability mode unknown"
          missing="info"
          description="jenkins2026.obsMode is missing from the runtime config - re-run scripts/08.95-backstage.sh (Day1 or Day2.redeploy.08) so the backstage-runtime-config ConfigMap carries OBS_MODE."
        />
      );
  }
};
