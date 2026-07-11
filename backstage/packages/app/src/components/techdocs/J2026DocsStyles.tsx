/*
 * TechDocs shadow-DOM style addon — GitHub-like overflow behaviour for the
 * repo docs WITHOUT touching the markdown.
 *
 * TechDocs renders the mkdocs site inside a shadow root, where this repo's
 * wide tables and large mermaid SVGs force the content column wider than the
 * viewport — the WHOLE page then scrolls horizontally and the left/right
 * sidebars (nav + page ToC) are pushed out of view. On GitHub every wide
 * element scrolls by itself; this addon injects that same contract into the
 * shadow DOM: the layout is clamped to the viewport and tables / code blocks
 * / mermaid diagrams get their own scrollbars.
 *
 * Registered (like the Mermaid addon) in BOTH TechDocsAddons blocks: the
 * standalone reader route (App.tsx) and the entity Docs tab (EntityPage.tsx).
 */
import { useEffect } from 'react';
import { createPlugin } from '@backstage/core-plugin-api';
import {
  createTechDocsAddonExtension,
  TechDocsAddonLocations,
  useShadowRootElements,
} from '@backstage/plugin-techdocs-react';

const STYLE_ID = 'j2026-docs-styles';

const CSS = `
/* Clamp the layout: the page itself never scrolls horizontally. */
.md-grid { max-width: 100%; }
.md-main__inner, .md-content, .md-content__inner { min-width: 0; }
.md-content { overflow-x: hidden; }

/* GitHub-style per-element scrollbars for anything wide. */
.md-typeset table:not([class]) {
  display: block;
  width: fit-content;
  max-width: 100%;
  overflow-x: auto;
}
.md-typeset pre > code {
  max-width: 100%;
  overflow-x: auto;
}

/* Mermaid diagrams (rendered client-side by the Mermaid addon): scale to the
 * column like GitHub does (mermaid's own inline max-width wins when set); the
 * container scrolls as a fallback so an unscaled SVG can never widen the page. */
.md-typeset .mermaid {
  max-width: 100%;
  overflow-x: auto;
}
.md-typeset .mermaid svg {
  max-width: 100%;
  height: auto;
}
`;

/** Injects the stylesheet once per shadow root; renders nothing. */
export const J2026DocsStylesAddon = () => {
  const [mdMain] = useShadowRootElements<HTMLElement>(['.md-main']);
  useEffect(() => {
    if (!mdMain) {
      return;
    }
    const root = mdMain.getRootNode();
    if (!(root instanceof ShadowRoot) || root.querySelector(`#${STYLE_ID}`)) {
      return;
    }
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS;
    root.appendChild(style);
  }, [mdMain]);
  return null;
};

const j2026TechdocsAddonsPlugin = createPlugin({
  id: 'j2026-techdocs-addons',
});

export const J2026DocsStyles = j2026TechdocsAddonsPlugin.provide(
  createTechDocsAddonExtension({
    name: 'J2026DocsStyles',
    location: TechDocsAddonLocations.Content,
    component: J2026DocsStylesAddon,
  }),
);
