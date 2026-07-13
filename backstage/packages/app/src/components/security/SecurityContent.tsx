/*
 * The Security tab (docs/601 § SARIF upload): GitHub Code Scanning (Semgrep +
 * CodeQL findings, cross-linked from docs/601) and Dependabot alerts for any
 * entity carrying github.com/project-slug - the SAME annotation the CI/CD
 * tab's GitHub Actions case already reads (see ../cicd/CicdContent), now that
 * all four CI engines upload SARIF against each entity's OWN repo rather than
 * always the infra repo (docs/601, fixed alongside this tab on 2026-07-13).
 *
 * Dependabot alerts additionally need that repo's own "Dependabot alerts"
 * repo setting enabled (GitHub Settings -> Code security - a manual, per-repo
 * toggle outside this platform's Terraform/scripts scope); until then the
 * card degrades to an inline error message, it does not crash the tab.
 *
 * @roadiehq/backstage-plugin-security-insights registers no API factory of
 * its own (it calls the GitHub REST API via the core scmAuthApiRef, already
 * wired in ../../apis.ts for the GitHub Actions tab) - unlike the Grafana
 * plugin, there is no static-tree children trick needed here.
 */
import React from 'react';
import { Grid } from '@material-ui/core';
import {
  EntitySecurityInsightsCard,
  EntityDependabotAlertsCard,
} from '@roadiehq/backstage-plugin-security-insights';

export const SecurityContent = () => (
  <Grid container spacing={3} alignItems="stretch">
    <Grid item md={6} xs={12}>
      <EntitySecurityInsightsCard />
    </Grid>
    <Grid item md={6} xs={12}>
      <EntityDependabotAlertsCard />
    </Grid>
  </Grid>
);
