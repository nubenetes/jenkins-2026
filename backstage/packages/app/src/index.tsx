import '@backstage/cli/asset-types';
// Backstage's global CSS (modern-normalize + the Backstage UI tokens). REQUIRED, not
// cosmetic: @backstage/theme 0.7.0 removed the built-in `CssBaseline` from
// UnifiedThemeProvider (a BREAKING change — "if your Backstage instance looks broken
// after this update, you likely forgot to add our new Backstage UI global CSS") and moved
// the reset here, for the app to import. We upgraded past it without adding this, so
// nothing set `box-sizing: border-box` and everything inherited the `content-box`
// default. SidebarPage's content wrapper is `width: 100%` PLUS a `padding-left` of the
// sidebar width, which under content-box ADD UP: the whole app rendered exactly one
// sidebar wider than the viewport (measured live: 2253px vs a 2037px viewport = 216px of
// horizontal scroll on every page, at any window size) and body kept its default 8px
// margin. See docs/505 § Troubleshooting.
import '@backstage/ui/css/styles.css';
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

ReactDOM.createRoot(document.getElementById('root')!).render(<App />);
