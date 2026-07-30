---
name: dotnet-lean-arch
description: "Use when creating a .NET backend/API from scratch or adding endpoints/use cases with pragmatic 4-layer Clean Architecture (.NET 10, no MediatR, Result pattern, EF Core, Aspire). Triggers: Clean Architecture, UseCase, IEndpoint, IApplicationDbContext."
version: 1.0.0
---

> **This skill is a portable blueprint.** The body below says *how to act*; the
> files in [`references/`](references/) hold the detail of each layer, pattern,
> practice, reference and guide. Links resolve via relative paths.


# 🤖 .NET Blueprint — Entry point

> **You (AI agent) are starting here.** This is the architectural blueprint
> for .NET backends. This document says **how to act**; the
> [index](references/index.md) is the **map** of all the content. Read this
> document in full, then use the [index](references/index.md) to navigate to
> whatever you need.

## How this skill is organized

```
dotnet-lean-arch/
├── SKILL.md         ← you are here (how to act)
└── references/
    ├── index.md                 ← navigation map (philosophy + dependency flow)
    ├── {domain,application,infra,api}-layer.md    ← the 4 layers
    ├── result-pattern.md, two-level-validation.md, typed-configuration.md  ← patterns
    ├── logging-observability.md, testing-strategy.md,
    │   external-service-integration.md, authentication-and-security.md,
    │   background-processing.md               ← cross-cutting practices
    ├── stack-and-dependencies.md, conventions-and-naming.md  ← reference
    └── how-to-add-{endpoint,usecase}.md           ← actionable guides
```

> All reference files live **flat** in `references/`; links between them are
> relative paths (e.g. `[domain-layer](references/domain-layer.md)`).

## ⚠️ Read before coding

1. Read the [index](references/index.md) (philosophy + dependency flow).
2. Read the four layers in order: [domain-layer](references/domain-layer.md) → [application-layer](references/application-layer.md) →
   [infra-layer](references/infra-layer.md) → [api-layer](references/api-layer.md).
3. Read [stack-and-dependencies](references/stack-and-dependencies.md) **before pinning any package** — always use
   the latest versions and confirm current syntax via Context7 / Microsoft Learn.
4. Keep [conventions-and-naming](references/conventions-and-naming.md) at hand as a quick reference.
5. Consult the practices as the task requires: [logging-observability](references/logging-observability.md),
   [testing-strategy](references/testing-strategy.md), [external-service-integration](references/external-service-integration.md).
6. Only then start writing code. Resist "jumping to the controller".

## Recommended implementation order

The order follows the direction of the dependencies — **inside-out**:

### 1. Domain (core, no dependencies)
- Create the shared types first: `Entity`, `AggregateRoot`,
  `DomainException`, `Result`/`Result<T>`, `Error`/`ErrorType`.
- Model the domain entities and value objects. See [domain-layer](references/domain-layer.md).

### 2. Application (orchestration)
- Define the `IApplicationDbContext` abstraction.
- Create the first UseCase (UseCase + Validator + Request + Response in the same
  file). See [application-layer](references/application-layer.md) and [how-to-add-usecase](references/how-to-add-usecase.md).
- Define the typed `Options` classes. See [typed-configuration](references/typed-configuration.md).
- If there is an external integration, define the `IXxxGateway` abstraction here.
  See [external-service-integration](references/external-service-integration.md).

### 3. Infra (details)
- Implement the `ApplicationDbContext : IApplicationDbContext`.
- Configure entities (`IEntityTypeConfiguration`), snake_case, migrations.
  See [infra-layer](references/infra-layer.md).
- Implement the external service gateways (Refit + ACL + resilience). See
  [external-service-integration](references/external-service-integration.md).

### 4. Api (entry + composition root)
- Implement the first `IEndpoint`. See [api-layer](references/api-layer.md) and [how-to-add-endpoint](references/how-to-add-endpoint.md).
- Configure `GlobalExceptionHandler` and `ResultExtensions`.
- Assemble `Program.cs`: Serilog + try/catch/finally, register services from all
  layers, map endpoints. See [logging-observability](references/logging-observability.md).
- **Keep the API up to date** when adding/changing endpoints (index + examples).
- Declare **authorization explicitly** on every endpoint
  (`.RequireAuthorization()` / `.AllowAnonymous()`). See [authentication-and-security](references/authentication-and-security.md).

### 5. Tests (in parallel, from the start)
- Domain unit tests (fast) and UseCase integration tests with TestContainers.
  See [testing-strategy](references/testing-strategy.md).

> Need async work outside the request? Use a **Job** (≠ UseCase) with
> Hangfire isolated in Infra. See [background-processing](references/background-processing.md).

## Scaffolding checklist

### Project folder structure
```
.
├── Directory.Build.props          # global defaults for all projects
├── Directory.Packages.props       # centralized package versions (CPM)
├── nuget.config                   # package sources
├── <Solution>.slnx                # solution file
├── aspire/
│   ├── <Solution>.AppHost/        # orchestration (optional)
│   └── <Solution>.ServiceDefaults/# OTel, health checks, service discovery, Serilog
├── src/
│   ├── <Solution>.Domain/
│   ├── <Solution>.Application/
│   ├── <Solution>.Infra/
│   └── <Solution>.Api/
└── tests/
    ├── <Solution>.UnitTests/
    └── integration/<Solution>.IntegrationTests/
```

### `Directory.Build.props` (root)
```xml
<Project>
    <PropertyGroup>
        <TargetFramework>net10.0</TargetFramework>
        <ImplicitUsings>enable</ImplicitUsings>
        <Nullable>enable</Nullable>
    </PropertyGroup>
</Project>
```

> Package versions and curation: see [stack-and-dependencies](references/stack-and-dependencies.md).

### `Directory.Packages.props` (Central Package Management)
```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <!-- Define the VERSION here; in the .csproj reference WITHOUT version -->
    <PackageVersion Include="FluentValidation.DependencyInjectionExtensions" Version="..." />
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="..." />
    <!-- ... -->
  </ItemGroup>
</Project>
```
> In the `.csproj` files: `<PackageReference Include="..." />` (no `Version`).

### Project references
- `Api.csproj` → references `Application` + `Infra` (+ `ServiceDefaults`).
- `Infra.csproj` → references `Application` (and transitively `Domain`).
- `Application.csproj` → references `Domain`.
- `Domain.csproj` → **no** project references.

### ServiceDefaults (if using orchestration)
Centralizes OpenTelemetry, health checks (`/health`, `/alive`), service discovery,
`HttpClient` resilience and the Serilog configuration. Exposed via
`AddServiceDefaults()` / `MapDefaultEndpoints()` called in `Program.cs`.
See [logging-observability](references/logging-observability.md).

## Scaffold definition of done

- [ ] Solution compiles with the 4 layers and correct dependencies.
- [ ] CPM active; no `.csproj` pins a package version.
- [ ] Base `Result`/`Error` and `Entity` exist in Domain.
- [ ] `IApplicationDbContext` defined in Application and implemented in Infra.
- [ ] At least one `IEndpoint` mapped and responding.
- [ ] `GlobalExceptionHandler` registered; errors become ProblemDetails.
- [ ] Serilog configured via `appsettings.json`; `Program.cs` in try/catch/finally
      with bootstrap logger and fallback file sink. See [logging-observability](references/logging-observability.md).
- [ ] `Program` accessible to tests (`public partial class Program;`); at least one
      UseCase integration test with TestContainers. See [testing-strategy](references/testing-strategy.md).
- [ ] External integrations (if any) behind `IXxxGateway` with ACL and resilience.
      See [external-service-integration](references/external-service-integration.md).
