/*
 * The portal landing page (docs/505 § Home page).
 *
 * NOT `ScorecardHomepageCard`: live-verified 2026-07-13 that
 * GET /api/scorecard/aggregations/github.open_prs 404s for every signed-in
 * user here - the scorecard backend's own docs confirm why ("User not in
 * catalog: 404 Not Found when applicable"). That card aggregates by ENTITY
 * OWNERSHIP (entities the user owns directly, or via a catalog Group they're
 * a direct member of), and this app's IAP sign-in deliberately runs with
 * `dangerouslyAllowSignInWithoutUserInCatalog: true` (../../apis.ts note in
 * App.tsx's SignInPage) - there are no catalog User/Group entities at all, so
 * ownership can never resolve. Not a race/config gap: structurally
 * incompatible with this platform's auth model until the roadmap's "Catalog
 * User auto-provision" item ships (docs/505 § Roadmap). A plain quick-links
 * card avoids promising a portfolio view that silently 404s for everyone.
 */
import React from 'react';
import { Grid } from '@material-ui/core';
import { Content, Header, InfoCard, Link, Page } from '@backstage/core-components';

export const HomePage = () => (
  <Page themeId="home">
    <Header title="jenkins-2026" subtitle="CI/CD platform + demo microservices" />
    <Content>
      <Grid container spacing={3}>
        <Grid item md={4} xs={12}>
          <InfoCard title="Quick links">
            <Grid container spacing={1} direction="column">
              <Grid item>
                <Link to="/catalog">Catalog</Link>
              </Grid>
              <Grid item>
                <Link to="/catalog/default/component/jenkins-2026-infra/monitoring">
                  Platform Monitoring
                </Link>
              </Grid>
              <Grid item>
                <Link to="/catalog/default/component/jenkins-2026-infra/security">
                  Platform Security
                </Link>
              </Grid>
              <Grid item>
                <Link to="/docs">Docs</Link>
              </Grid>
              <Grid item>
                <Link to="/catalog-graph">Graph</Link>
              </Grid>
            </Grid>
          </InfoCard>
        </Grid>
      </Grid>
    </Content>
  </Page>
);
