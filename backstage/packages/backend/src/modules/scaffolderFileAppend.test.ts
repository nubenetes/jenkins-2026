/**
 * @jest-environment node
 */
/*
 * Tests for the j2026:file:append custom Scaffolder action.
 *
 * This action writes real PRs against the three append-only registries a service
 * is declared in, so a "green run" that emitted subtly-corrupt YAML would be worse
 * than a red one. These tests lock in the invariants the action's comments claim:
 *   - it APPENDS, never rewrites (existing bytes, comments included, are untouched);
 *   - the join is exactly one newline, no matter the surrounding whitespace;
 *   - `anchor` is a substring gate on the whole file (shape guard);
 *   - `absent` is a per-LINE, trimmed equality gate (dup guard) — and must NOT
 *     mistake `name: gateway` for an existing `name: gateway-v2`;
 *   - a missing file and a path-traversal path both fail loudly.
 *
 * The action's handler only ever touches ctx.input / ctx.workspacePath /
 * ctx.logger.info, so we hand-roll a minimal context (cast to any) over a real
 * tmp workspace — no @backstage/*-test-utils dependency needed.
 */
import { createFileAppendAction } from './scaffolderFileAppend';
import { mkdtemp, readFile, writeFile, rm } from 'fs/promises';
import { tmpdir } from 'os';
import { join } from 'path';

const action = createFileAppendAction();

type Input = {
  path: string;
  content: string;
  anchor?: string;
  absent?: string;
};

function run(workspacePath: string, input: Input) {
  const ctx: any = {
    workspacePath,
    input,
    logger: { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} },
    getInitiatorCredentials: async () => ({}),
  };
  return action.handler(ctx);
}

describe('j2026:file:append', () => {
  let workspace: string;

  beforeEach(async () => {
    workspace = await mkdtemp(join(tmpdir(), 'j2026-append-'));
  });

  afterEach(async () => {
    await rm(workspace, { recursive: true, force: true });
  });

  const seed = (name: string, body: string) =>
    writeFile(join(workspace, name), body, 'utf8');
  const readBack = (name: string) => readFile(join(workspace, name), 'utf8');

  it('appends without disturbing existing content or comments', async () => {
    // A file whose comments carry the design rationale, exactly like services.yaml.
    await seed(
      'services.yaml',
      '# the registry ALL FOUR engines read\nservices:\n  - name: gateway\n',
    );

    await run(workspace, {
      path: 'services.yaml',
      content: '  - name: neo\n',
    });

    expect(await readBack('services.yaml')).toBe(
      '# the registry ALL FOUR engines read\nservices:\n  - name: gateway\n  - name: neo\n',
    );
  });

  it('joins with exactly one newline regardless of surrounding whitespace', async () => {
    // Existing file ends with a blob of trailing whitespace; content is padded with
    // leading newlines. The join must collapse both to a single '\n' and end in '\n'.
    await seed('f.txt', 'first\n\n  \n');

    await run(workspace, { path: 'f.txt', content: '\n\nsecond' });

    expect(await readBack('f.txt')).toBe('first\nsecond\n');
  });

  it('accepts the append when the anchor is present', async () => {
    await seed('f.yaml', 'services:\n  - a\n');
    await expect(
      run(workspace, { path: 'f.yaml', content: '  - b\n', anchor: 'services:' }),
    ).resolves.toBeUndefined();
    expect(await readBack('f.yaml')).toBe('services:\n  - a\n  - b\n');
  });

  it('refuses when the anchor is missing (file shape changed)', async () => {
    await seed('f.yaml', 'items:\n  - a\n');
    await expect(
      run(workspace, { path: 'f.yaml', content: '  - b\n', anchor: 'services:' }),
    ).rejects.toThrow(/does not contain the expected anchor/);
    // The file must be left untouched on failure.
    expect(await readBack('f.yaml')).toBe('items:\n  - a\n');
  });

  it('refuses a duplicate entry (absent matches an existing line)', async () => {
    await seed('catalog.yaml', 'metadata:\n  name: gateway\n');
    await expect(
      run(workspace, {
        path: 'catalog.yaml',
        content: 'metadata:\n  name: gateway\n',
        absent: 'name: gateway',
      }),
    ).rejects.toThrow(/already has a line/);
  });

  it('matches absent per-line trimmed, ignoring indentation', async () => {
    // The existing line is deeply indented; the needle has none. Trimmed equality
    // must still catch it.
    await seed('catalog.yaml', 'x:\n        name: gateway\n');
    await expect(
      run(workspace, {
        path: 'catalog.yaml',
        content: 'name: gateway\n',
        absent: 'name: gateway',
      }),
    ).rejects.toThrow(/already has a line/);
  });

  it('does NOT treat absent as a substring (gateway must not match gateway-v2)', async () => {
    // The whole point of the per-line comparison: a longer, distinct entry is not a dup.
    await seed('catalog.yaml', 'metadata:\n  name: gateway-v2\n');
    await expect(
      run(workspace, {
        path: 'catalog.yaml',
        content: '  name: gateway\n',
        absent: 'name: gateway',
      }),
    ).resolves.toBeUndefined();
    expect(await readBack('catalog.yaml')).toBe(
      'metadata:\n  name: gateway-v2\n  name: gateway\n',
    );
  });

  it('fails loudly when the target file does not exist', async () => {
    await expect(
      run(workspace, { path: 'nope.yaml', content: 'x\n' }),
    ).rejects.toThrow(/does not exist in the workspace/);
  });

  it('refuses to escape the workspace (path traversal)', async () => {
    // resolveSafeChildPath must reject an upward path before any read/write happens.
    await expect(
      run(workspace, { path: '../escape.yaml', content: 'x\n' }),
    ).rejects.toThrow();
  });
});
