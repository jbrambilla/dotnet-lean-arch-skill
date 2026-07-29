# dotnet-lean-arch

> Clean Architecture pragmatica para backends .NET. Sem overkill.

Agent Skill ([padrao aberto](https://agentskills.io)) que guia o agente na construcao
de backends .NET: 4 camadas (Domain, Application, Infra, Api) organizadas em slices,
sem MediatR, Result pattern, validacao em dois niveis, configuracao tipada, EF Core,
Aspire e Serilog/OpenTelemetry. Implementacao de dentro para fora, com checklist de
scaffolding, definition of done e 17 arquivos de referencia.

Funciona em qualquer agente compativel com Agent Skills: Claude Code, claude.ai,
OpenAI Codex, GitHub Copilot / VS Code, Cursor, Gemini CLI, OpenCode, entre outros.

## Instalacao

**Claude Code (marketplace):**

```
/plugin marketplace add jbrambilla/dotnet-lean-arch-skill
/plugin install dotnet-lean-arch@jbrambilla
```

**Qualquer agente (Codex, Copilot, Cursor, Gemini CLI, OpenCode...):**

```bash
git clone https://github.com/jbrambilla/dotnet-lean-arch-skill.git
ln -s "$(pwd)/dotnet-lean-arch-skill/skills/dotnet-lean-arch" ~/.agents/skills/dotnet-lean-arch
```

`~/.agents/skills/` e a convencao universal; Claude Code usa `~/.claude/skills/`.
No Windows sem Developer Mode, copie a pasta em vez de linkar. `git pull` no clone
atualiza a skill (symlink aponta para o working tree).

**claude.ai:** baixe o ZIP da ultima [Release](https://github.com/jbrambilla/dotnet-lean-arch-skill/releases)
e envie em Settings > Capabilities > Skills > Upload skill.

## Uso

Peca um backend .NET em linguagem natural — "cria uma API .NET do zero para gestao
de pedidos" — e a skill dispara sozinha. Gatilhos e escopo vivem na `description`
do [SKILL.md](skills/dotnet-lean-arch/SKILL.md).

## Estrutura

```
skills/dotnet-lean-arch/
├── SKILL.md          # instrucoes principais + description de disparo
└── references/       # 17 referencias: camadas, result pattern, validacao,
                      # testes, observabilidade, auth, background jobs...
```

Indice completo em [references/index.md](skills/dotnet-lean-arch/references/index.md).

## Contribuindo

Toda mudanca via PR com CI verde; commits seguem
[Conventional Commits](https://www.conventionalcommits.org). Regras de
versionamento e manutencao: [AGENTS.md](AGENTS.md) e [CHANGELOG](CHANGELOG.md).

## Licenca

[MIT](LICENSE)
