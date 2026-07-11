/*
 * Rewrites in-cluster service URLs to their public IAP hosts in every anchor
 * the SPA renders.
 *
 * WHY: the community CI/CD plugins build their deep links from the SAME base
 * URL their BACKENDS call — argocd 2.9.0 from `metadata.instance.url`
 * (always injected by its backend; `argocd.baseUrl` is a dead fallback),
 * jenkins from the instance `baseUrl` — and those URLs must stay INTERNAL:
 * the public hosts sit behind IAP, which 302s the plugins' server-to-server
 * calls (docs/505 § Troubleshooting). Until upstream separates the data URL
 * from the link URL, this shim gives users working links: a MutationObserver
 * rewrites matching hrefs IN PLACE (so hover, copy-link and middle-click all
 * show the public URL too), mapping
 *
 *   http://argocd-server.argocd.svc.cluster.local[:80]/...  -> https://argocd.<baseDomain>/...
 *   http://jenkins.jenkins.svc.cluster.local:8080|8082/...  -> https://jenkins.<baseDomain>/...
 *
 * Path-compatible by construction (same apps, same routes). Self-contained
 * and deletable the day the plugins grow a frontendUrl-style option.
 */
import { useEffect } from 'react';
import { useApi, configApiRef } from '@backstage/core-plugin-api';

const INTERNAL_HOSTS: Array<{ pattern: RegExp; app: string }> = [
  {
    pattern: /^https?:\/\/argocd-server\.argocd(\.svc(\.cluster\.local)?)?(:\d+)?/i,
    app: 'argocd',
  },
  {
    pattern: /^https?:\/\/jenkins\.jenkins(\.svc(\.cluster\.local)?)?(:\d+)?/i,
    app: 'jenkins',
  },
];

export const InternalUrlRewriter = () => {
  const config = useApi(configApiRef);
  const baseDomain = config.getOptionalString('jenkins2026.baseDomain');

  useEffect(() => {
    if (!baseDomain) {
      return undefined;
    }
    const rewriteIn = (root: ParentNode) => {
      root.querySelectorAll?.('a[href]').forEach(a => {
        const href = a.getAttribute('href');
        if (!href) {
          return;
        }
        for (const { pattern, app } of INTERNAL_HOSTS) {
          if (pattern.test(href)) {
            a.setAttribute(
              'href',
              href.replace(pattern, `https://${app}.${baseDomain}`),
            );
            // External IAP-protected app: open in its own tab.
            (a as HTMLAnchorElement).target = '_blank';
            (a as HTMLAnchorElement).rel = 'noopener';
            break;
          }
        }
      });
    };
    rewriteIn(document.body);
    // Only childList mutations are observed, and the rewrite touches href
    // attributes — no observer feedback loop.
    const observer = new MutationObserver(mutations => {
      for (const mutation of mutations) {
        mutation.addedNodes.forEach(node => {
          if (node instanceof Element) {
            rewriteIn(node);
          }
        });
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
    return () => observer.disconnect();
  }, [baseDomain]);

  return null;
};
