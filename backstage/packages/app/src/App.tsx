import React from 'react';
import { Navigate, Route } from 'react-router-dom';
import { ApiExplorerPage, apiDocsPlugin } from '@backstage/plugin-api-docs';
import {
  CatalogEntityPage,
  CatalogIndexPage,
  catalogPlugin,
} from '@backstage/plugin-catalog';
import { CatalogGraphPage } from '@backstage/plugin-catalog-graph';
import { orgPlugin } from '@backstage/plugin-org';
import { SearchPage } from '@backstage/plugin-search';
import {
  TechDocsIndexPage,
  techdocsPlugin,
  TechDocsReaderPage,
} from '@backstage/plugin-techdocs';
import { TechDocsAddons } from '@backstage/plugin-techdocs-react';
import { Mermaid } from 'backstage-plugin-techdocs-addon-mermaid';
import { UserSettingsPage } from '@backstage/plugin-user-settings';
import { J2026DocsStyles } from './components/techdocs/J2026DocsStyles';
import { apis } from './apis';
import { entityPage } from './components/catalog/EntityPage';
import { searchPage } from './components/search/SearchPage';
import { Root } from './components/Root';
import { InternalUrlRewriter } from './components/Root/InternalUrlRewriter';

import {
  AlertDisplay,
  OAuthRequestDialog,
  ProxiedSignInPage,
  SignInPage,
} from '@backstage/core-components';
import { createApp } from '@backstage/app-defaults';
import { AppRouter, FlatRoutes } from '@backstage/core-app-api';
import { configApiRef, useApi } from '@backstage/core-plugin-api';

const app = createApp({
  apis,
  components: {
    // Production sits behind Google IAP: the gcpIap auth provider verifies the
    // IAP-signed JWT server-side, so there is NO interactive login - the
    // ProxiedSignInPage resolves the identity transparently. Local dev
    // (auth.environment=development + the guest provider, see
    // app-config.local.example.yaml) falls back to the guest sign-in.
    SignInPage: props => {
      const configApi = useApi(configApiRef);
      if (configApi.getString('auth.environment') === 'development') {
        return <SignInPage {...props} providers={['guest']} />;
      }
      return <ProxiedSignInPage {...props} provider="gcpIap" />;
    },
  },
  bindRoutes({ bind }) {
    bind(catalogPlugin.externalRoutes, {
      viewTechDoc: techdocsPlugin.routes.docRoot,
    });
    bind(orgPlugin.externalRoutes, {
      catalogIndex: catalogPlugin.routes.catalogIndex,
    });
    // No scaffolder / catalog-import in this app (docs/505 § Roadmap), so
    // apiDocs' registerApi external route stays deliberately unbound.
    bind(apiDocsPlugin.externalRoutes, {});
  },
});

const routes = (
  <FlatRoutes>
    <Route path="/" element={<Navigate to="catalog" />} />
    <Route path="/catalog" element={<CatalogIndexPage />} />
    <Route
      path="/catalog/:namespace/:kind/:name"
      element={<CatalogEntityPage />}
    >
      {entityPage}
    </Route>
    <Route path="/docs" element={<TechDocsIndexPage />} />
    <Route
      path="/docs/:namespace/:kind/:name/*"
      element={<TechDocsReaderPage />}
    >
      <TechDocsAddons>
        {/* Renders the repo docs' ```mermaid blocks client-side. */}
        <Mermaid />
        {/* GitHub-like overflow: wide tables/code/diagrams scroll themselves
            instead of widening the page (keeps both sidebars in view). */}
        <J2026DocsStyles />
      </TechDocsAddons>
    </Route>
    <Route path="/api-docs" element={<ApiExplorerPage />} />
    <Route path="/search" element={<SearchPage />}>
      {searchPage}
    </Route>
    <Route path="/catalog-graph" element={<CatalogGraphPage />} />
    <Route path="/settings" element={<UserSettingsPage />} />
  </FlatRoutes>
);

export default app.createRoot(
  <>
    <AlertDisplay />
    <OAuthRequestDialog />
    {/* In-cluster URLs (argocd-server.argocd.svc…, jenkins.jenkins.svc…) in
        plugin deep links -> the public IAP hosts. See the component header. */}
    <InternalUrlRewriter />
    <AppRouter>
      <Root>{routes}</Root>
    </AppRouter>
  </>,
);
