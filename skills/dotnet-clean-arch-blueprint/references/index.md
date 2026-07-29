---
tags: [arquitetura, dotnet, moc, blueprint]
aliases: [MOC Arquitetura, Mapa do Vault]
---
# 🗺️ Blueprint de Arquitetura .NET

> Mapa central (MOC) deste vault. Documenta um **padrão arquitetural agnóstico**
> para qualquer backend .NET. Copie esta pasta para o esqueleto de novos projetos.

> 🤖 **Agente de IA?** Comece pelo [AGENTS](../SKILL.md) (como atuar); volte aqui para navegar.
> 🌐 **Endpoints da API:** API (índice da superfície HTTP — o *que* a app expõe).

## Filosofia

Arquitetura **pragmática**, focada em clareza e manutenibilidade — sem
sofisticação desnecessária. Os pilares:

- **Clean Architecture em 4 camadas** — dependências sempre apontam para dentro.
- **Sem MediatR** — casos de uso são classes [UseCase](camada-application.md)
  simples injetadas por DI. Menos cerimônia, menos indireção.
- **[Result pattern](result-pattern.md)** — fluxo de negócio é controlado por
  `Result<T>`/`Error`, **nunca** por exceções.
- **[Validação em dois níveis](validacao-dois-niveis.md)** — FluentValidation para
  formato/entrada; `DomainException` para invariantes de domínio.
- **[Configuração tipada](configuracao-tipada.md)** — `Options` com DataAnnotations
  e `ValidateOnStart()`: a aplicação falha no boot se a config estiver inválida.
- **[Endpoints auto-registrados](camada-api.md)** — cada rota é uma classe
  `IEndpoint` descoberta por varredura de assembly. Zero registro manual de rota.

## Fluxo de dependências

```
        ┌─────────────────────────────────────────┐
        │                   Api                    │  Minimal API, IEndpoint,
        │         (composição da raiz)             │  ExceptionHandler
        └───────────────┬─────────────────────────┘
                        │ depende de
                        ▼
        ┌─────────────────────────────────────────┐
        │              Application                 │  UseCases, Validators,
        │   (IApplicationDbContext, Options)       │  abstrações
        └───────────────┬─────────────────────────┘
                        │ depende de
                        ▼
        ┌─────────────────────────────────────────┐
        │                Domain                    │  Entities, Value Objects,
        │        (sem dependências externas)       │  Result/Error, Entity base
        └─────────────────────────────────────────┘
                        ▲
                        │ implementa abstrações de Application
                        │ e depende de Domain
        ┌───────────────┴─────────────────────────┐
        │                 Infra                    │  EF Core, persistência,
        │   (implementa IApplicationDbContext)     │  serviços externos
        └─────────────────────────────────────────┘
```

**Regra de ouro das dependências:**
- `Api → Application → Domain`
- `Infra → Application` (implementa abstrações) `+ Infra → Domain`
- `Domain` **não referencia nada**.
- A `Api` compõe a raiz: referencia `Application` e `Infra` para montar o DI.

## Navegação

> A pasta de cada nota indica sua natureza: `camadas/`, `padroes/`, `praticas/`,
> `referencia/`, `guias/`. (Wikilinks resolvem por nome, independente da pasta.)

### 🧱 Camadas (`camadas/`)
- [camada-domain](camada-domain.md) — entidades, value objects, `Entity` base, `Result`/`Error`.
- [camada-application](camada-application.md) — UseCases, validators, `IApplicationDbContext`, options.
- [camada-infra](camada-infra.md) — EF Core, configurações, migrations, serviços externos.
- [camada-api](camada-api.md) — Minimal API, `IEndpoint`, exception handling.

### 🎯 Padrões de arquitetura (`padroes/`)
- [result-pattern](result-pattern.md) — controle de fluxo sem exceções.
- [validacao-dois-niveis](validacao-dois-niveis.md) — FluentValidation vs DomainException.
- [configuracao-tipada](configuracao-tipada.md) — Options validadas no boot.

### 🛠️ Práticas transversais (`praticas/`)
- [logging-observabilidade](logging-observabilidade.md) — Serilog via appsettings, OTLP + fallback em arquivo.
- [estrategia-de-testes](estrategia-de-testes.md) — unitário de domínio + integração de UseCase com TestContainers.
- [integracao-servico-externo](integracao-servico-externo.md) — Refit + ACL + resiliência + TokenManager para APIs externas.
- [autenticacao-e-seguranca](autenticacao-e-seguranca.md) — API Key (autorização explícita por endpoint) + panorama (JWT, EF Identity).
- [processamento-em-segundo-plano](processamento-em-segundo-plano.md) — background jobs com Hangfire (Job ≠ UseCase).

### 📚 Referência (`referencia/`)
- [stack-e-dependencias](stack-e-dependencias.md) — packages-base e como manter versões/sintaxe atuais (Context7 / MS Learn).
- [convencoes-e-nomenclatura](convencoes-e-nomenclatura.md) — nota-cola: sufixos, estrutura de pastas, rotas, visibilidade.

### 📘 Guias acionáveis (`guias/`)
- [como-adicionar-endpoint](como-adicionar-endpoint.md) — adicionar uma rota nova do zero.
- [como-adicionar-usecase](como-adicionar-usecase.md) — adicionar um caso de uso novo do zero.

### 🤖 Para agentes
- [AGENTS](../SKILL.md) — ponto de entrada: como atuar, ordem de implementação e checklist de scaffolding.

## Convenções gerais

- **Idioma:** domínio, classes, mensagens e logs em **português**.
- **Pacotes:** versões centralizadas (Central Package Management).
- **Defaults globais:** `TargetFramework`, `Nullable`, `ImplicitUsings` em
  `Directory.Build.props` — nunca redefinir por projeto.
