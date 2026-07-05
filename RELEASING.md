# Releasing

How versions, the changelog, tags, and GitHub releases fit together for
**jenkins-2026** — designed so the history stays easy to track and scales without
the file (or the release list) becoming noise.

## The model at a glance

| Artifact | Where | Granularity |
| :--- | :--- | :--- |
| Ongoing changes | `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md) | per PR (a bullet each) |
| A release | `## [vX.Y.Z]` section in `CHANGELOG.md` | **one milestone** |
| Git tag | `vX.Y.Z` on `main` | **1:1 with the release section** |
| GitHub release | notes = that section's body | **1:1 with the tag** |
| Old history (≤ v0.28.56) | [`CHANGELOG-ARCHIVE.md`](CHANGELOG-ARCHIVE.md) | frozen, kept out of the live file |

**One granularity, three places in sync.** A version exists as a CHANGELOG section
*and* a tag *and* a GitHub release — never a tag without a release, never a release
without a section. That is what makes the [release index](CHANGELOG.md#release-index)
a faithful map of the history.

## Conventions

1. **Accumulate under `[Unreleased]`.** When a PR merges to `develop`, add a bullet
   under `## [Unreleased]` in `CHANGELOG.md` in the right group (`### Added`,
   `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`, `Documentation`), citing
   the `(#NNN)`. No version decision per PR.
2. **Version — `v1.0.0` is the stable baseline.** From 1.0 on: **minor** (`v1.Y.0`) at a
   feature milestone, **patch** (`v1.Y.Z`) for a hotfix on a released line, **major**
   (`v2.0.0`) for a breaking change. Cut at a coherent milestone, not per PR — that is why
   there is no `vX.Y.1…56` churn.

   > **Version history & the 1.0 baseline.** The `v0.x` line (v0.1.0 – v0.29.0) was rapid
   > **pre-1.0 development**: fast iteration, inconsistent numbering (gaps + a long
   > `v0.28.x` patch series), releases cut at ad-hoc points. Those releases are a **frozen
   > historical record** — they are **never renumbered**, because rewriting a shipped
   > version breaks version immutability (a SemVer/Keep-a-Changelog anti-pattern) and
   > erases the real chronology. `v1.0.0` draws a clean line: it declares the reference PoC
   > feature-complete and starts the disciplined milestone cadence above. Detail for
   > **≤ v0.28.56** lives in [`CHANGELOG-ARCHIVE.md`](CHANGELOG-ARCHIVE.md); v0.29.0 (the
   > last v0.x) and v1.0.0 onward are in [`CHANGELOG.md`](CHANGELOG.md).
3. **Keep `CHANGELOG.md` lean.** It holds `[Unreleased]`, the current release(s), and
   the index. When it grows, move the oldest full sections into
   `CHANGELOG-ARCHIVE.md` and leave their index row pointing there (verbatim — never
   rewrite archived entries; backfills are the one documented exception).

## Cutting a release

Two phases, following the repo's `develop → main` GitFlow, both driven by
[`scripts/cut-release.sh`](scripts/cut-release.sh):

### 1. Prepare (on `develop`)

```bash
scripts/cut-release.sh v1.2.0          # or: v1.2.0 2026-07-15 to pin the date
```

This renames `## [Unreleased]` → `## [v1.2.0] - <today>`, opens a fresh empty
`## [Unreleased]`, and inserts a Release-index row (edit its `_set me_` theme). Then:

```bash
git add CHANGELOG.md
git commit -m "release: v1.2.0"
# open + merge a PR from develop to main (gitflow-guard required check)
```

It refuses to run if `[Unreleased]` has no entries, or if the tag already exists.

### 2. Publish (on `main`, after the prepare PR merges)

```bash
git checkout main && git pull
scripts/cut-release.sh v1.2.0 --publish
```

This tags `main` at HEAD and runs `gh release create`, using the version's
`CHANGELOG.md` section body as the release notes and its leading `_italic_` summary
as the title suffix. It refuses if the tag or GitHub release already exists.

## Hotfix on a released line

Land the fix on `develop` under `[Unreleased]`, then cut `vX.Y.(Z+1)` the same way.
(There is no long-lived release branch in this PoC — `main` is the single released
line.)

## Notes

- **Never hand-create a tag or GitHub release** outside this flow — it would break the
  1:1 invariant the index relies on. Use `--publish`.
- The archive is append-frozen. If you discover an *undocumented* historical change,
  backfill it into its version section in `CHANGELOG-ARCHIVE.md` citing the PR (as was
  done during the v0.29.0 consolidation), not into `CHANGELOG.md`.
