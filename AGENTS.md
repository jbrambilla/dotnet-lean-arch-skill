# AGENTS.md

Guia de manutencao para agentes de codigo (Claude Code, Codex, Cursor, Gemini CLI
etc.) trabalhando neste repositorio. Claude Code le este arquivo via import no
`CLAUDE.md`.

## O que este repositorio e

Repositorio de UMA Agent Skill (`dotnet-lean-arch`) — nao ha codigo de aplicacao.
Todo o conteudo e markdown + manifestos JSON. "Buildar" e "testar" significam
validar integridade e rodar os casos de disparo.

A skill tem identidade dupla a partir da mesma pasta:

- **Agent Skill (padrao aberto)**: `skills/dotnet-lean-arch/` e autocontida —
  qualquer agente compativel le `SKILL.md` + `references/`.
- **Plugin do Claude Code**: `skills/dotnet-lean-arch/.claude-plugin/plugin.json`
  (manifesto do plugin) + `.claude-plugin/marketplace.json` na raiz (catalogo).
  As demais ferramentas ignoram essas pastas.

## Comando principal

```bash
bash scripts/validate.sh
```

Unico comando do repo. CI (`.github/workflows/validate.yml`) roda ele em todo
push/PR. Checa: frontmatter obrigatorio, `description` <= 250 chars, SKILL.md
<= 500 linhas, versao sincronizada nos 3 manifestos, ausencia de caminhos
absolutos e de credenciais. Rode SEMPRE antes de commitar.

## Arquitetura do conteudo

- `skills/dotnet-lean-arch/SKILL.md` — ponto de entrada: diz ao agente COMO atuar
  (ordem de implementacao de dentro pra fora, checklist de scaffolding, definition
  of done). Nao duplica detalhe tecnico.
- `skills/dotnet-lean-arch/references/` — 17 arquivos FLAT (sem subpastas), um por
  camada/padrao/pratica. `index.md` e o mapa de navegacao. Links entre arquivos sao
  SEMPRE caminhos relativos (`references/camada-domain.md`) — caminho absoluto
  reprova no validate.
- `evals/cases.md` — 10 casos manuais de disparo (6 positivos, 4 negativos). Mudou
  a `description` do SKILL.md? Rode todos de novo em sessao nova.

## Versionamento (regra critica)

Versao existe em TRES lugares e deve ser identica no mesmo PR (validate falha se
divergir): frontmatter do `SKILL.md`, `plugin.json` e `marketplace.json`.

- **MAJOR**: skill passa a produzir estrutura incompativel (camadas, contratos base
  como `Result`/`IEndpoint`).
- **MINOR**: qualquer mudanca de comportamento — instrucoes no SKILL.md, arquivos de
  `references/`, nova pratica. Alterar a `description` e MINOR no minimo (muda o
  disparo).
- **PATCH**: typo, formatacao, docs do repo (README, CHANGELOG), CI.

Toda mudanca de versao exige entrada no `CHANGELOG.md` (Keep a Changelog, pt-BR).

## Release

Tag `v<versao>` (ex.: `v1.1.0`) dispara `.github/workflows/release.yml`, que gera o
ZIP da skill (excluindo `.claude-plugin/`) e anexa na GitHub Release. O ZIP precisa
ter a pasta `dotnet-lean-arch/` na raiz — e o formato que o claude.ai aceita no
upload manual.

## Convencoes

- Commits: [Conventional Commits](https://www.conventionalcommits.org), descricao
  em pt-BR.
- Docs do repositorio (README, CHANGELOG, este arquivo): pt-BR sem acentos (ascii).
  Conteudo da skill (`SKILL.md`, `references/`): pt-BR com acentos.
- Nunca cite caminhos absolutos ou credenciais em nenhum arquivo — validate reprova.
