# dotnet-lean-arch

> Pragmatic Clean Architecture for .NET backends. No overkill.

A skill that teaches coding agents to build consistent, testable .NET backends.
Without it, agents swing between two extremes: dumping all the logic into the
endpoint, or applying dogmatic Clean Architecture full of unnecessary abstraction
(MediatR, generic repositories, layers that just forward calls). The skill locks in
the pragmatic middle ground: 4 layers with dependencies pointing inward, Result
pattern for business flow, two-level validation, EF Core, Aspire and
observability, all with minimal external dependencies. The same predictable
pattern from the initial scaffold to the nth endpoint.

Works with Claude Code, claude.ai, Codex, Copilot, Cursor, Gemini CLI, OpenCode and
any agent that reads the [SKILL.md](https://agentskills.io) format.

## Install

**One command, every agent** — [`npx skills`](https://skills.sh) detects the coding
agents installed on your machine (Claude Code, Codex, Copilot/VS Code, Cursor,
Gemini CLI, OpenCode and 70+ more) and installs into each one:

```bash
npx skills add jbrambilla/dotnet-lean-arch-skill
```

**No Node?** Same result via the bundled installer, which copies the skill to
`~/.claude/skills/` and `~/.agents/skills/`:

```bash
curl -fsSL https://raw.githubusercontent.com/jbrambilla/dotnet-lean-arch-skill/main/install.sh | bash
```

Re-run either command to update; `bash -s -- --uninstall` removes it.

**Claude Code as a plugin** (managed updates via `/plugin`):

```bash
claude plugin marketplace add jbrambilla/dotnet-lean-arch-skill && claude plugin install dotnet-lean-arch@jbrambilla
```

Or inside a session: `/plugin marketplace add jbrambilla/dotnet-lean-arch-skill`,
then `/plugin install dotnet-lean-arch@jbrambilla`.

**claude.ai:** download the ZIP from the latest [Release](https://github.com/jbrambilla/dotnet-lean-arch-skill/releases)
and upload it under Settings > Capabilities > Skills > Upload skill.

## Usage

Ask for a .NET backend in natural language ("create a .NET API from scratch for
order management") and the skill triggers on its own. Triggers and scope live in
the `description` of [SKILL.md](skills/dotnet-lean-arch/SKILL.md).

## Structure

```
skills/dotnet-lean-arch/
├── SKILL.md          # main instructions + triggering description
└── references/       # 17 references: layers, result pattern, validation,
                      # testing, observability, auth, background jobs...
```

Full index at [references/index.md](skills/dotnet-lean-arch/references/index.md).

## Contributing

Every change goes through a PR with green CI; commits follow
[Conventional Commits](https://www.conventionalcommits.org). Versioning and
maintenance rules: [AGENTS.md](AGENTS.md) and [CHANGELOG](CHANGELOG.md).

## License

[MIT](LICENSE)
