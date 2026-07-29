# dotnet-lean-arch-skill

Agent Skill ([padrao aberto](https://agentskills.io)): **dotnet-lean-arch** — Clean
Architecture pragmatica para backends .NET, sem overkill.

Funciona em qualquer agente compativel com o formato Agent Skills (`SKILL.md`):
Claude Code, claude.ai, OpenAI Codex, GitHub Copilot / VS Code, Cursor, Gemini CLI,
OpenCode, entre outros. Para Claude Code ha ainda distribuicao via plugin/marketplace.

## O que a skill faz

Blueprint arquitetural para backends .NET com Clean Architecture pragmatica: 4 camadas
(Domain, Application, Infra, Api) organizadas em slices, sem MediatR, Result pattern,
validacao em dois niveis, configuracao tipada, EF Core, Aspire e Serilog/OpenTelemetry.
A filosofia e evitar overkill: nada de padroes complexos onde simplicidade resolve, e o
minimo possivel de dependencias externas.

Quando ativa, a skill guia o agente por uma ordem de implementacao de dentro para fora
(Domain, Application, Infra, Api, Testes), com checklist de scaffolding, definition of
done e 17 arquivos de referencia detalhando cada camada, padrao e pratica.

### Frases que ativam a skill

- "Cria uma API em .NET do zero para gestao de pedidos"
- "Monta um backend C# novo seguindo Clean Architecture"
- "Faz o scaffolding de uma solucao .NET 10 com EF Core e Aspire"
- "Adiciona um endpoint de cancelamento de pedido nessa API"
- "Cria um UseCase de importacao de notas com validacao"
- Mencoes a UseCase, IEndpoint, IApplicationDbContext ou Result pattern em contexto .NET

## Quando NAO usar

| Cenario | Use no lugar |
| --- | --- |
| Preferencias de estilo/convencoes que valem para todo projeto, sempre | `CLAUDE.md` / `AGENTS.md` do projeto ou global |
| Acao automatica disparada por evento (ex.: rodar formatter apos cada edicao) | Hook em `settings.json` |
| Acao manual e deterministica que voce mesmo invoca (ex.: gerar migration) | Slash command / skill invocavel por comando |
| Console apps, workers simples, frontends, ou projetos que nao seguem este padrao | Nao ativar; resposta direta do agente |
| Manutencao pontual (bugfix) em API existente sem novo endpoint/usecase | Nao ativar; a skill e para construir, nao para depurar |

## Instalacao

### 1. Claude Code via marketplace (recomendado)

```
/plugin marketplace add jbrambilla/dotnet-lean-arch-skill
/plugin install dotnet-lean-arch@jbrambilla
```

Atualizacoes chegam via `/plugin` (Manage plugins) quando o repositorio publicar nova versao.

### 2. Claude Code via clone + symlink

```bash
git clone https://github.com/jbrambilla/dotnet-lean-arch-skill.git
```

Linux/macOS:

```bash
ln -s "$(pwd)/dotnet-lean-arch-skill/skills/dotnet-lean-arch" ~/.claude/skills/dotnet-lean-arch
```

Windows (PowerShell, como administrador ou com Developer Mode ativo):

```powershell
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\skills\dotnet-lean-arch" -Target "$PWD\dotnet-lean-arch-skill\skills\dotnet-lean-arch"
```

`git pull` no clone atualiza a skill automaticamente (o symlink aponta para o working tree).

### 3. claude.ai / Cowork via upload de ZIP

1. Baixe o ZIP da ultima [GitHub Release](https://github.com/jbrambilla/dotnet-lean-arch-skill/releases)
   (gerado automaticamente a cada tag `v*`), ou gere localmente:

   ```bash
   cd skills
   zip -r ../dotnet-lean-arch.zip dotnet-lean-arch -x "dotnet-lean-arch/.claude-plugin/*"
   ```

   Importante: a PASTA `dotnet-lean-arch/` deve estar na raiz do ZIP
   (`dotnet-lean-arch/SKILL.md`), nao os arquivos soltos.

2. No claude.ai: Settings > Capabilities > Skills > Upload skill, e envie o ZIP.

### 4. Outras ferramentas (Codex, Copilot/VS Code, Cursor, Gemini CLI, OpenCode)

Essas ferramentas compartilham a convencao universal de diretorio `.agents/skills`:

- Global (vale para todos os projetos): `~/.agents/skills/`
- Por projeto: `.agents/skills/` na raiz do repositorio

Linux/macOS:

```bash
git clone https://github.com/jbrambilla/dotnet-lean-arch-skill.git
ln -s "$(pwd)/dotnet-lean-arch-skill/skills/dotnet-lean-arch" ~/.agents/skills/dotnet-lean-arch
```

Windows (PowerShell, admin ou Developer Mode; sem privilegio, copie em vez de linkar):

```powershell
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.agents\skills\dotnet-lean-arch" -Target "$PWD\dotnet-lean-arch-skill\skills\dotnet-lean-arch"
```

Se a sua ferramenta usa outro diretorio (ex.: versoes antigas do Codex com
`~/.codex/skills/`), copie ou linke a MESMA pasta `skills/dotnet-lean-arch/` para la —
o conteudo e identico, so muda o local de descoberta. A subpasta `.claude-plugin/` e
metadado exclusivo do Claude Code e e ignorada pelas demais ferramentas.

## Verificacao pos-instalacao

- Claude Code: rode `/plugin` e confira o plugin instalado e habilitado; ou pergunte
  em uma sessao nova: "quais skills voce tem disponiveis?" e confira
  `dotnet-lean-arch` na lista.
- Teste de disparo: "Cria uma API .NET do zero para cadastro de clientes". O agente
  deve anunciar o uso da skill e comecar pela leitura do index/camadas, nao pelo controller.
- claude.ai: abra uma conversa nova e confira a skill em Settings > Capabilities > Skills
  (toggle ativo), depois rode o mesmo teste de disparo.
- Outras ferramentas: pergunte "quais skills voce tem disponiveis?" em sessao nova e
  confira `dotnet-lean-arch` na lista; depois rode o mesmo teste de disparo.

## Troubleshooting

**Skill nao dispara**

1. Cheque a `description` primeiro. E o UNICO criterio de disparo automatico: o modelo
   ve apenas `name` + `description` de cada skill e decide carregar o corpo quando o
   pedido bate com esse texto. Se o seu fraseado nao tem relacao com os gatilhos da
   description, o disparo nao acontece. Reformule o pedido ou ajuste a description
   (isso conta como MINOR, ver CHANGELOG).
2. Sessao iniciada antes da instalacao nao enxerga a skill: abra uma sessao nova.
3. Confirme o caminho: skills de plugin vivem em `skills/<nome>/SKILL.md` dentro do
   plugin; skills pessoais do Claude Code em `~/.claude/skills/<nome>/SKILL.md`; demais
   ferramentas em `~/.agents/skills/<nome>/SKILL.md` (ou o diretorio proprio da
   ferramenta). Pastas com outro nome (ex.: `.skills/`) nao sao descobertas.
4. Symlink no Windows exige privilegio: sem admin/Developer Mode, o `New-Item` cria
   atalho invalido. Alternativa: copie a pasta em vez de linkar.
5. Rode `bash scripts/validate.sh` no repo: frontmatter invalido impede o carregamento.

**Skill dispara demais**: restrinja a description (remova gatilhos genericos) e abra PR.

## Como contribuir

- Toda mudanca via Pull Request. Commit direto na `main` e proibido (configure branch
  protection no GitHub exigindo PR + CI verde).
- O CI roda `scripts/validate.sh` em todo push e PR; o merge exige validacao verde.
- Mudou comportamento da skill (instrucoes, references, description)? Incremente a
  versao nos TRES lugares (SKILL.md, plugin.json, marketplace.json) e adicione entrada
  no CHANGELOG.md. Regras de versionamento no proprio CHANGELOG.
- Commits seguem [Conventional Commits](https://www.conventionalcommits.org).
- Release: apos merge, crie tag `v<versao>` (ex.: `v1.1.0`); o workflow gera o ZIP e
  anexa na GitHub Release.
