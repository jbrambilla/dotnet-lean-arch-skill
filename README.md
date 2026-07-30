# dotnet-lean-arch

> Clean Architecture pragmatica para backends .NET. Sem overkill.

Skill que ensina agentes de codigo a construir backends .NET consistentes e
testaveis. Sem ela, o agente oscila entre dois extremos: despeja a logica toda no
endpoint, ou aplica Clean Architecture dogmatica, cheia de abstracao desnecessaria
(MediatR, repositorios genericos, camadas que so repassam chamada). A skill fixa o
meio-termo pragmatico: 4 camadas com dependencias apontando para dentro, Result
pattern no fluxo de negocio, validacao em dois niveis, EF Core, Aspire e
observabilidade, tudo com o minimo de dependencias externas. O mesmo padrao
previsivel do scaffold inicial ao enesimo endpoint.

Funciona em Claude Code, claude.ai, Codex, Copilot, Cursor, Gemini CLI, OpenCode e
qualquer agente que leia o formato [SKILL.md](https://agentskills.io).

## Instalação

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
