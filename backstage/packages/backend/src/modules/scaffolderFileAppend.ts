/*
 * j2026:file:append — the one custom Scaffolder action this platform needs.
 *
 * WHY THIS EXISTS (docs/505 § Scaffolder): onboarding a service here is not
 * "create files", it is "add one entry to three files that already exist":
 *   1. jenkins/pipelines/seed/services.yaml  — the registry ALL FOUR engines read
 *   2. backstage/catalog/services.yaml       — the catalog entity + its annotations
 *   3. gitops-config helm/microservices/values-stable.yaml — the deploy config
 * The stock actions can only WRITE whole files, and `fetch:template` rendering
 * those three from scratch would clobber anything a human edited by hand. Parsing
 * + merging YAML would need a real YAML round-trip (and would reformat/strip the
 * comments those files are full of — they carry most of the design rationale).
 *
 * All three files happen to be APPEND-ONLY by construction (verified before
 * writing this): `services:` is the LAST key of both YAMLs, and the catalog file
 * is a multi-document stream. So a new service is always a pure append — no
 * parsing, no merging, no reformatting, comments untouched. That is the whole
 * trick, and why this action is ~40 lines instead of a YAML-manipulation library.
 *
 * If that assumption ever breaks (someone adds a key AFTER `services:`), this
 * action silently appends into the wrong place — so it asserts `anchor`: the text
 * the file must currently END with. A mismatch fails the template loudly instead
 * of opening a subtly-corrupt PR.
 */
import { createBackendModule, resolveSafeChildPath } from '@backstage/backend-plugin-api';
import {
  createTemplateAction,
  scaffolderActionsExtensionPoint,
} from '@backstage/plugin-scaffolder-node';
import { readFile, writeFile } from 'fs/promises';

export const createFileAppendAction = () =>
  createTemplateAction({
    id: 'j2026:file:append',
    description:
      'Appends content to an existing file in the workspace, asserting what the file currently ends with. For append-only registries (services.yaml, the catalog stream, gitops values) — keeps their comments and formatting intact.',
    schema: {
      input: {
        path: z =>
          z.string().describe('Workspace-relative path of the file to append to'),
        content: z => z.string().describe('Text to append verbatim'),
        anchor: z =>
          z
            .string()
            .optional()
            .describe(
              'If set, the file must already CONTAIN this text, otherwise the action fails. Guards against appending into a file whose shape changed (e.g. a key added after `services:`).',
            ),
        absent: z =>
          z
            .string()
            .optional()
            .describe(
              'If set, NO line of the file may already equal this (compared trimmed), otherwise the action fails. Guards against appending a duplicate entry — appending is blind, and YAML happily accepts two list items with the same name.',
            ),
      },
    },
    async handler(ctx) {
      const { path, content, anchor, absent } = ctx.input;
      // resolveSafeChildPath refuses to escape the workspace (path traversal).
      const filePath = resolveSafeChildPath(ctx.workspacePath, path);

      let existing: string;
      try {
        existing = await readFile(filePath, 'utf8');
      } catch {
        throw new Error(
          `j2026:file:append: ${path} does not exist in the workspace. This action only EXTENDS files that are already there — it is not a substitute for fetch:template.`,
        );
      }

      if (anchor && !existing.includes(anchor)) {
        throw new Error(
          `j2026:file:append: ${path} does not contain the expected anchor ${JSON.stringify(
            anchor,
          )}. The file's shape changed, so appending would put the entry in the wrong place — refusing rather than opening a corrupt PR.`,
        );
      }

      // Compared per-LINE and trimmed, never as a substring: `name: gateway` must not
      // match an existing `name: gateway-v2`.
      if (absent) {
        const needle = absent.trim();
        if (existing.split('\n').some(line => line.trim() === needle)) {
          throw new Error(
            `j2026:file:append: ${path} already has a line ${JSON.stringify(
              needle,
            )}. Appending is blind, and YAML accepts duplicate entries happily — a second one would silently shadow the first (the seed job would re-point an existing service's pipeline at the new repo). Refusing.`,
          );
        }
      }

      // Exactly one newline between the old content and the new entry.
      const joined = `${existing.replace(/\s*$/, '')}\n${content.replace(/^\n+/, '')}`;
      await writeFile(filePath, joined.endsWith('\n') ? joined : `${joined}\n`, 'utf8');

      ctx.logger.info(`Appended ${content.length} chars to ${path}`);
    },
  });

export const scaffolderModuleFileAppend = createBackendModule({
  pluginId: 'scaffolder',
  moduleId: 'j2026-file-append',
  register(reg) {
    reg.registerInit({
      deps: { scaffolder: scaffolderActionsExtensionPoint },
      async init({ scaffolder }) {
        scaffolder.addActions(createFileAppendAction());
      },
    });
  },
});

// Default export: `backend.add(import('./modules/scaffolderFileAppend'))` resolves
// the module's default, exactly like the @backstage/* plugin packages it sits next to.
export default scaffolderModuleFileAppend;
