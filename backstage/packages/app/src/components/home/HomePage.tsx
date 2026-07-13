/*
 * The portal landing page (docs/505 § Home page): a portfolio-wide view that
 * complements the per-entity Scorecard tab (../catalog/EntityPage.tsx) with
 * an aggregated card across every entity that carries github.com/project-slug.
 *
 * ScorecardHomepageCard ships in the SAME package as the Scorecard tab
 * (@red-hat-developer-hub/backstage-plugin-scorecard) - no new dependency.
 * aggregationId="github.open_prs" needs no scorecard.aggregationKPIs config:
 * per the backend's own fallback rule, GET /aggregations/:aggregationId works
 * with the default statusGrouped aggregation when the id equals a metric id
 * directly (docs/505 § Scorecard tab).
 */
import React from 'react';
import { Grid } from '@material-ui/core';
import { Content, Header, Page } from '@backstage/core-components';
import { ScorecardHomepageCard } from '@red-hat-developer-hub/backstage-plugin-scorecard';

export const HomePage = () => (
  <Page themeId="home">
    <Header title="jenkins-2026" subtitle="CI/CD platform + demo microservices" />
    <Content>
      <Grid container spacing={3}>
        <Grid item md={4} xs={12}>
          <ScorecardHomepageCard aggregationId="github.open_prs" />
        </Grid>
      </Grid>
    </Content>
  </Page>
);
