# Changelog

All notable changes to this repository are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
versioning follows [Semantic Versioning](https://semver.org/).

## Versioning rules for this skill

- **MAJOR**: breaking change — the skill starts producing structure incompatible
  with the previous one (e.g. changes to the layers, to base contracts such as
  `Result`/`IEndpoint`, or removal of a practice existing projects rely on).
- **MINOR**: any change to the skill's behavior — new or modified instructions in
  SKILL.md, changes to `references/` files, a new practice or guide.
  **Any change to the SKILL.md `description` counts as AT LEAST minor**, since it
  changes when the skill triggers.
- **PATCH**: fixes that do not change behavior — typos, formatting, repository
  documentation (README, CHANGELOG), CI tweaks.
- The version must be updated in three places within the same PR: `SKILL.md`
  (frontmatter), `plugin.json` and `marketplace.json`. `scripts/validate.sh` fails
  if they diverge.

## [1.1.0] - 2026-07-30

### Added

- Explicit `InternalsVisibleTo` rule in `conventions-and-naming.md`: always declare
  it as an MSBuild item in the `.csproj`, never as a `Properties/AssemblyInfo.cs`
  with the `[assembly: InternalsVisibleTo(...)]` attribute. Lists the only two
  legitimate cases (`Domain` → `Infra`, `Api` → `IntegrationTests`).
- `Domain.csproj` snippet with `<InternalsVisibleTo Include="<Sln>.Infra" />` in
  `domain-layer.md`, right after the `Entity` base — the layer's `internal` setters
  now state how the access is granted.
- Scaffold definition-of-done item in `SKILL.md` covering the `Domain.csproj`
  declaration and the absence of any `AssemblyInfo.cs`.

### Fixed

- Contradiction between `conventions-and-naming.md` ("Entities: `private` setters")
  and the `Entity` base (`internal set` on `CreatedAt`/`UpdatedAt`) — the exception
  is now documented, so the agent no longer improvises the access mechanism.

## [1.0.0] - 2026-07-29

### Added

- `dotnet-lean-arch` skill: pragmatic Clean Architecture blueprint for .NET
  backends — 4 layers (Domain, Application, Infra, Api), no MediatR, Result
  pattern, two-level validation, typed configuration, EF Core, Aspire,
  Serilog/OpenTelemetry, with 17 reference files.
- Claude Code plugin packaging: `.claude-plugin/plugin.json` in the skill and
  `.claude-plugin/marketplace.json` at the repository root.
- `README.md` with usage instructions and three installation paths.
- `evals/cases.md` with manual trigger cases (positive and negative).
- `scripts/validate.sh` with checks for frontmatter, size, version sync,
  absolute paths and credentials.
- CI workflows: validation on push/PR and release with a ZIP attached on `v*` tags.
- `LICENSE` (MIT) and `.gitignore` with an explicit allowlist.

### Changed

- Skill renamed from `dotnet-clean-arch-blueprint` to `dotnet-lean-arch`.
- SKILL.md `description` rewritten from 574 to 244 characters, leading with the
  main use case and keeping the technical triggers.
- All repository and skill content translated to English (reference files renamed
  to English names) to serve the worldwide community; evals keep 2 pt-BR cases to
  guarantee cross-language triggering.
