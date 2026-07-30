# AGENTS.md

Maintenance guide for coding agents (Claude Code, Codex, Cursor, Gemini CLI,
etc.) working in this repository. Claude Code reads this file via the import in
`CLAUDE.md`.

## What this repository is

Repository of ONE Agent Skill (`dotnet-lean-arch`) — there is no application code.
All content is markdown + JSON manifests. "Building" and "testing" mean validating
integrity and running the trigger cases.

The skill has a dual identity from the same folder:

- **Agent Skill (open standard)**: `skills/dotnet-lean-arch/` is self-contained —
  any compatible agent reads `SKILL.md` + `references/`.
- **Claude Code plugin**: `skills/dotnet-lean-arch/.claude-plugin/plugin.json`
  (plugin manifest) + `.claude-plugin/marketplace.json` at the root (catalog).
  Other tools ignore these folders.

## Main command

```bash
bash scripts/validate.sh
```

The repo's only command. CI (`.github/workflows/validate.yml`) runs it on every
push/PR. It checks: required frontmatter, `description` <= 250 chars, SKILL.md
<= 500 lines, version in sync across the 3 manifests, no absolute paths and no
credentials. ALWAYS run it before committing.

## Content architecture

- `skills/dotnet-lean-arch/SKILL.md` — entry point: tells the agent HOW to act
  (inside-out implementation order, scaffolding checklist, definition of done).
  Does not duplicate technical detail.
- `skills/dotnet-lean-arch/references/` — 17 FLAT files (no subfolders), one per
  layer/pattern/practice. `index.md` is the navigation map. Links between files are
  ALWAYS relative paths (`references/domain-layer.md`) — absolute paths fail
  validation.
- `evals/cases.md` — 12 manual trigger cases (8 positive, including 2 in pt-BR for
  cross-language triggering, and 4 negative). Changed the `description` in
  SKILL.md? Run them all again in a fresh session.

## Versioning (critical rule)

The version exists in THREE places and must be identical within the same PR
(validation fails if they diverge): `SKILL.md` frontmatter, `plugin.json` and
`marketplace.json`.

- **MAJOR**: the skill starts producing incompatible structure (layers, base
  contracts such as `Result`/`IEndpoint`).
- **MINOR**: any behavior change — instructions in SKILL.md, files in
  `references/`, a new practice. Changing the `description` is AT LEAST minor
  (it changes triggering).
- **PATCH**: typo, formatting, repo docs (README, CHANGELOG), CI.

Every version change requires an entry in `CHANGELOG.md` (Keep a Changelog).

## Release

Tag `v<version>` (e.g. `v1.1.0`) triggers `.github/workflows/release.yml`, which
builds the skill ZIP (excluding `.claude-plugin/`) and attaches it to the GitHub
Release. The ZIP must have the `dotnet-lean-arch/` folder at its root — that is
the format claude.ai accepts for manual upload.

## Conventions

- Commits: [Conventional Commits](https://www.conventionalcommits.org), in English.
- All content (repo docs and skill content) is written in English.
- Never include absolute paths or credentials in any file — validation fails.
