---
tags: [arquitetura, dotnet, convencoes, nomenclatura, referencia]
aliases: [Convenções e Nomenclatura, Convenções, Naming]
---

# 🧭 Convenções e Nomenclatura

> Nota-cola de **referência rápida**. Consolida as convenções que aparecem
> espalhadas pelas notas de camada e guias. Quando em dúvida sobre "como nomear"
> ou "onde colocar", consulte aqui.

Ver também: [index](index.md) · [camada-application](camada-application.md) · [camada-api](camada-api.md) · [camada-infra](camada-infra.md) · [stack-e-dependencias](stack-e-dependencias.md)

## Idioma

- **Domínio, classes, propriedades, mensagens de erro e logs em português.**
- Termos técnicos consagrados ficam no original (`Endpoint`, `UseCase`, `Request`,
  `Response`, `Options`). Não traduza o que vira nome de tipo do padrão.

## Estrutura de pastas

Organização **por feature/recurso**, não por tipo técnico.

```
src/<Sln>.Domain/
├── Shared/                         # Entity, AggregateRoot, Result, Error, DomainException
├── ValueObjects/                   # value objects (Email, Codigo, ...)
└── <Entidade>.cs                   # entidades na raiz do Domain

src/<Sln>.Application/
├── Abstractions/                   # IApplicationDbContext e outras abstrações
├── Features/<Recurso>/             # 1 pasta por recurso
│   └── <Acao>UseCase.cs            # Validator + UseCase + Request + Response juntos
└── DependencyInjection.cs

src/<Sln>.Infra/
├── Persistence/
│   ├── ApplicationDbContext.cs
│   ├── Configurations/             # IEntityTypeConfiguration por entidade
│   └── Migrations/
├── ExternalServices/<Provedor>/    # integrações (sessão futura)
└── DependencyInjection.cs

src/<Sln>.Api/
├── Endpoints/<Recurso>/<Acao>.cs   # 1 classe IEndpoint por ação
├── Endpoints/Tags.cs
├── Extensions/                     # EndpointExtensions, ResultExtensions, ...
├── Handlers/                       # GlobalExceptionHandler
└── Program.cs
```

## Sufixos de tipos

| Tipo | Sufixo / forma | Exemplo |
| ---- | -------------- | ------- |
| Caso de uso | `*UseCase` | `CriarWidgetUseCase` |
| Validador (FluentValidation) | `*Validator` | `CriarWidgetValidator` |
| Entrada do UseCase (`record`) | `*Request` | `CriarWidgetRequest` |
| Saída do UseCase (`record`) | `*Response` | `CriarWidgetResponse` |
| Endpoint (`IEndpoint`) | nome = **ação** (sem sufixo) | `CriarWidget`, `ObterWidgetPorId` |
| Config EF de entidade | `*Configuration` | `WidgetConfiguration` |
| Options tipadas | `*Options` | `WidgetOptions` |
| Exceção de domínio | `DomainException` | (única, em `Shared`) |

> **Um arquivo por caso de uso** agrupa Validator + UseCase + Request + Response,
> nessa ordem. Ver [camada-application](camada-application.md).

## Escolha class × record

- **`record`** — para DTOs imutáveis: `Request`, `Response`, `Error`.
- **`class`** — para tipos com identidade/comportamento: entidades, value objects,
  `UseCase`, `Validator`, `Options`, `DbContext`.

## Visibilidade

- **Endpoints:** `internal sealed` (descobertos por varredura, não precisam ser públicos).
- **Entidades:** `sealed`, setters `private`, construtor `private` sem args para o EF Core.
- **Validators:** `sealed`.
- **Options:** `sealed`.
- **Tipos varridos por assembly** (endpoints, validators, configurations) não
  precisam ser `public` — a varredura usa `DefinedTypes`/`includeInternalTypes`.

## Namespaces

Seguem a estrutura de pastas: `<Sln>.<Camada>.<Pasta>...`
(ex.: `Blueprint.Application.Features.Widgets`).

## Rotas HTTP

- Versionadas e no plural: **`api/v{n}/<recurso>`** (ex.: `api/v1/widgets`).
- Sub-recursos/ações encadeiam o caminho: `api/v1/widgets/{id:guid}/bars`.
- Use **route constraints** quando o tipo for conhecido: `{id:guid}`, `{ano:int}`.
- Agrupe no OpenAPI com `.WithTags(Tags.<Recurso>)` — constantes em `Endpoints/Tags.cs`.
- Documente o contrato de sucesso com `.Produces<TResponse>(StatusCodes.Status200OK)`.

## Assíncrono e cancelamento

- Métodos de I/O são `async`/`Task<...>`.
- **Propague `CancellationToken` sempre** — do endpoint → UseCase → EF Core. Os
  handlers de Minimal API recebem o token por injeção.
- O método público do UseCase é `Execute(request, cancellationToken)` (sem sufixo
  `Async` — convenção deste blueprint, por ser o único método público).

## Identidade e timestamps

- **Id:** `Guid` gerado com **`Guid.CreateVersion7()`** (ordenável por tempo),
  na base `Entity`.
- **`CriadoAs` / `AtualizadoAs`:** preenchidos automaticamente no
  `SaveChangesAsync` (setter `internal`). Não escreva à mão. Ver [camada-infra](camada-infra.md).

## Banco de dados

- Tabelas e colunas em **snake_case** (via convenção automática), sem anotar
  propriedade por propriedade.
- Uma `IEntityTypeConfiguration<T>` por entidade, aplicada por
  `ApplyConfigurationsFromAssembly`.

## Registro no DI

- **UseCases:** registro **manual** como `Scoped` em `Application/DependencyInjection.cs`.
- **Validators:** varredura automática (`AddValidatorsFromAssembly`).
- **Endpoints:** varredura automática (`AddEndpoints` + `MapEndpoints`).
- **Options:** `AddOptions<T>().Bind(...).ValidateDataAnnotations().ValidateOnStart()`.

## Princípios

- **Consistência > preferência pessoal:** siga o padrão existente mesmo que você
  faria diferente num projeto solo.
- **Organize por recurso**, não por tipo técnico (nada de pasta `Validators/`
  global separada dos UseCases).
- **Nomes revelam intenção** em português; o sufixo revela o papel arquitetural.
