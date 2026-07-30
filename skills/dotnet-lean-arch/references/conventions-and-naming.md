---
tags: [architecture, dotnet, conventions, naming, reference]
aliases: [Conventions and Naming, Conventions, Naming]
---

# 🧭 Conventions and Naming

> **Quick-reference** cheat sheet. Consolidates the conventions that appear
> scattered across the layer notes and guides. When in doubt about "how to name"
> or "where to put it", check here.

See also: [index](index.md) · [application-layer](application-layer.md) · [api-layer](api-layer.md) · [infra-layer](infra-layer.md) · [stack-and-dependencies](stack-and-dependencies.md)

## Language

- **Domain, classes, properties, error messages, and logs follow the team's
  ubiquitous language** — the language the business speaks. The examples in this
  skill use English; if the user or the existing codebase uses another language,
  follow it consistently.
- Well-established technical terms keep their original form (`Endpoint`, `UseCase`, `Request`,
  `Response`, `Options`). Do not translate what becomes a pattern type name.

## Folder structure

Organized **by feature/resource**, not by technical type.

```
src/<Sln>.Domain/
├── Shared/                         # Entity, AggregateRoot, Result, Error, DomainException
├── ValueObjects/                   # value objects (Email, Code, ...)
└── <Entity>.cs                     # entities at the Domain root

src/<Sln>.Application/
├── Abstractions/                   # IApplicationDbContext and other abstractions
├── Features/<Resource>/            # 1 folder per resource
│   └── <Action>UseCase.cs          # Validator + UseCase + Request + Response together
└── DependencyInjection.cs

src/<Sln>.Infra/
├── Persistence/
│   ├── ApplicationDbContext.cs
│   ├── Configurations/             # IEntityTypeConfiguration per entity
│   └── Migrations/
├── ExternalServices/<Provider>/    # integrations (future section)
└── DependencyInjection.cs

src/<Sln>.Api/
├── Endpoints/<Resource>/<Action>.cs # 1 IEndpoint class per action
├── Endpoints/Tags.cs
├── Extensions/                     # EndpointExtensions, ResultExtensions, ...
├── Handlers/                       # GlobalExceptionHandler
└── Program.cs
```

## Type suffixes

| Type | Suffix / form | Example |
| ---- | ------------- | ------- |
| Use case | `*UseCase` | `CreateWidgetUseCase` |
| Validator (FluentValidation) | `*Validator` | `CreateWidgetValidator` |
| UseCase input (`record`) | `*Request` | `CreateWidgetRequest` |
| UseCase output (`record`) | `*Response` | `CreateWidgetResponse` |
| Endpoint (`IEndpoint`) | name = **action** (no suffix) | `CreateWidget`, `GetWidgetById` |
| EF entity configuration | `*Configuration` | `WidgetConfiguration` |
| Typed options | `*Options` | `WidgetOptions` |
| Domain exception | `DomainException` | (single, in `Shared`) |

> **One file per use case** groups Validator + UseCase + Request + Response,
> in that order. See [application-layer](application-layer.md).

## Choosing class × record

- **`record`** — for immutable DTOs: `Request`, `Response`, `Error`.
- **`class`** — for types with identity/behavior: entities, value objects,
  `UseCase`, `Validator`, `Options`, `DbContext`.

## Visibility

- **Endpoints:** `internal sealed` (discovered by scanning, they don't need to be public).
- **Entities:** `sealed`, `private` setters, parameterless `private` constructor for EF Core.
  The **only exception** is `CreatedAt`/`UpdatedAt` on the `Entity` base — `internal set`,
  written solely by Infra. See [domain-layer](domain-layer.md).
- **Validators:** `sealed`.
- **Options:** `sealed`.
- **Assembly-scanned types** (endpoints, validators, configurations) don't need
  to be `public` — scanning uses `DefinedTypes`/`includeInternalTypes`.

### `InternalsVisibleTo`

- Always declare it as an **MSBuild item** in the `.csproj`:
  `<InternalsVisibleTo Include="<Assembly>" />`.
- **Never** create `Properties/AssemblyInfo.cs`, and never use the
  `[assembly: InternalsVisibleTo(...)]` attribute — legacy .NET Framework style.
- Only two legitimate cases in this blueprint:
  - `Domain.csproj` → `<Sln>.Infra` (timestamp setters). See [domain-layer](domain-layer.md).
  - `Api.csproj` → `<Sln>.IntegrationTests` (optional, only if `public partial class Program;`
    is not used). See [testing-strategy](testing-strategy.md).

## Namespaces

Follow the folder structure: `<Sln>.<Layer>.<Folder>...`
(e.g., `Blueprint.Application.Features.Widgets`).

## HTTP routes

- Versioned and plural: **`api/v{n}/<resource>`** (e.g., `api/v1/widgets`).
- Sub-resources/actions chain onto the path: `api/v1/widgets/{id:guid}/bars`.
- Use **route constraints** when the type is known: `{id:guid}`, `{year:int}`.
- Group in OpenAPI with `.WithTags(Tags.<Resource>)` — constants in `Endpoints/Tags.cs`.
- Document the success contract with `.Produces<TResponse>(StatusCodes.Status200OK)`.

## Async and cancellation

- I/O methods are `async`/`Task<...>`.
- **Always propagate `CancellationToken`** — from endpoint → UseCase → EF Core.
  Minimal API handlers receive the token via injection.
- The UseCase's public method is `Execute(request, cancellationToken)` (no `Async`
  suffix — this blueprint's convention, since it is the only public method).

## Identity and timestamps

- **Id:** `Guid` generated with **`Guid.CreateVersion7()`** (time-orderable),
  in the `Entity` base.
- **`CreatedAt` / `UpdatedAt`:** filled automatically in
  `SaveChangesAsync` (`internal` setter). Never set them by hand. See [infra-layer](infra-layer.md).
  Infra gets write access through `<InternalsVisibleTo Include="<Sln>.Infra" />` in
  `Domain.csproj` — an MSBuild item, never an `AssemblyInfo.cs`.

## Database

- Tables and columns in **snake_case** (via automatic convention), without
  annotating property by property.
- One `IEntityTypeConfiguration<T>` per entity, applied via
  `ApplyConfigurationsFromAssembly`.

## DI registration

- **UseCases:** **manual** registration as `Scoped` in `Application/DependencyInjection.cs`.
- **Validators:** automatic scanning (`AddValidatorsFromAssembly`).
- **Endpoints:** automatic scanning (`AddEndpoints` + `MapEndpoints`).
- **Options:** `AddOptions<T>().Bind(...).ValidateDataAnnotations().ValidateOnStart()`.

## Principles

- **Consistency > personal preference:** follow the existing pattern even if you
  would do it differently in a solo project.
- **Organize by resource**, not by technical type (no global `Validators/`
  folder separate from the UseCases).
- **Names reveal intent** in the team's ubiquitous language; the suffix reveals the architectural role.
