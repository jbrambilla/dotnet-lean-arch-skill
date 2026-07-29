# Changelog

Todas as mudancas relevantes deste repositorio sao documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o
versionamento segue [Semantic Versioning](https://semver.org/lang/pt-BR/).

## Regras de versionamento desta skill

- **MAJOR**: breaking change — a skill passa a produzir estrutura incompativel com a
  anterior (ex.: mudanca nas camadas, nos contratos base como `Result`/`IEndpoint`,
  ou remocao de pratica que projetos existentes seguem).
- **MINOR**: qualquer mudanca de comportamento da skill — instrucoes novas ou
  alteradas no SKILL.md, mudancas em arquivos de `references/`, nova pratica ou guia.
  **Qualquer alteracao na `description` do SKILL.md conta como MINOR no minimo**,
  pois muda quando a skill dispara.
- **PATCH**: correcoes que nao mudam comportamento — typos, formatacao, documentacao
  do repositorio (README, CHANGELOG), ajustes de CI.
- A versao deve ser atualizada em tres lugares no mesmo PR: `SKILL.md` (frontmatter),
  `plugin.json` e `marketplace.json`. O `scripts/validate.sh` falha se divergirem.

## [1.0.0] - 2026-07-29

### Added

- Skill `dotnet-lean-arch`: blueprint de Clean Architecture pragmatica para
  backends .NET — 4 camadas (Domain, Application, Infra, Api), sem MediatR, Result
  pattern, validacao em dois niveis, configuracao tipada, EF Core, Aspire,
  Serilog/OpenTelemetry, com 17 arquivos de referencia.
- Empacotamento como plugin do Claude Code: `.claude-plugin/plugin.json` na skill e
  `.claude-plugin/marketplace.json` na raiz do repositorio.
- `README.md` com instrucoes de uso, tres caminhos de instalacao, verificacao e
  troubleshooting.
- `evals/cases.md` com 10 casos de disparo (6 positivos, 4 negativos).
- `scripts/validate.sh` com checagens de frontmatter, tamanho, sincronia de versao,
  caminhos absolutos e credenciais.
- Workflows de CI: validacao em push/PR e release com ZIP anexado em tags `v*`.
- `LICENSE` (MIT) e `.gitignore` com allowlist explicito.

### Changed

- Skill renomeada de `dotnet-clean-arch-blueprint` para `dotnet-lean-arch`.
- `description` do SKILL.md reescrita de 574 para 244 caracteres, iniciando pelo caso
  de uso principal e mantendo os gatilhos tecnicos.
