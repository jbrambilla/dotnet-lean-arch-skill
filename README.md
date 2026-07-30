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

## Installation

**Claude Code (marketplace):**

```
/plugin marketplace add jbrambilla/dotnet-lean-arch-skill
/plugin install dotnet-lean-arch@jbrambilla
```

**Any agent (Codex, Copilot, Cursor, Gemini CLI, OpenCode...):**

```bash
git clone https://github.com/jbrambilla/dotnet-lean-arch-skill.git
ln -s "$(pwd)/dotnet-lean-arch-skill/skills/dotnet-lean-arch" ~/.agents/skills/dotnet-lean-arch
```

`~/.agents/skills/` is the universal convention; Claude Code uses `~/.claude/skills/`.
On Windows without Developer Mode, copy the folder instead of symlinking. `git pull`
in the clone updates the skill (the symlink points to the working tree).

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
