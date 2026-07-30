---
tags: [architecture, dotnet, stack, dependencies, packages, mcp]
aliases: [Stack and Dependencies, Packages, Base Packages]
---

# 📦 Stack and Dependencies

> Curated list of the base packages and — **more importantly** — the guideline
> on how to pick versions and syntax when starting a new project with this blueprint.

See also: [index](index.md) · [AGENTS](../SKILL.md) · [logging-observability](logging-observability.md) · [typed-configuration](typed-configuration.md)

## ⚠️ Core guideline (read before adding any package)

This blueprint is **version-agnostic**. When instantiating a new project:

1. **Always use the latest stable version** of .NET, C#, and every package — never
   copy "fossilized" version numbers from here.
2. **Do not rely on training knowledge alone** for APIs, signatures, patterns,
   and package names. They change. **Confirm against the sources of truth below.**
3. **Take advantage of new C# syntax** when the current version offers something
   better (e.g., collection expressions, the `field` keyword, primary constructors,
   new pattern matching, etc.) — as long as it improves clarity, not for novelty's sake.

### Sources of truth (MCPs)

- **Context7** — up-to-date documentation for libraries/frameworks (EF Core,
  FluentValidation, Serilog, OpenTelemetry, Aspire...). Use it **before** writing
  configuration or API calls for any package.
- **Microsoft Learn** — official reference for .NET, C#, and the Microsoft
  ecosystem (language features, `Microsoft.Extensions.*` APIs, EF Core, ASP.NET
  Core). Use it to confirm the most recent syntax/feature.

> Rule of thumb: **before pinning a package in `Directory.Packages.props` or using
> a new API, do a quick check on Context7 and/or Microsoft Learn.** It is cheap
> and prevents code that is already outdated at the project's birth.

## Version management — CPM

Versions are centralized in `Directory.Packages.props` (Central Package
Management). See [AGENTS](../SKILL.md).

- In the central file: `<PackageVersion Include="..." Version="..." />`.
- In the `.csproj` files: `<PackageReference Include="..." />` (**without** `Version`).

## Base packages by category

**Reference** list of what typically makes up this stack — **without versions**
on purpose (confirm the latest at the time). Include only what the project actually uses.

### Persistence (EF Core + PostgreSQL)
- `Microsoft.EntityFrameworkCore` — ORM.
- `Microsoft.EntityFrameworkCore.Design` — migrations tooling (private assets).
- `Npgsql.EntityFrameworkCore.PostgreSQL` — PostgreSQL provider.
- `EFCore.NamingConventions` — automatic **snake_case** convention. See [infra-layer](infra-layer.md).

### Validation
- `FluentValidation.DependencyInjectionExtensions` — validators + assembly-based
  registration. See [two-level-validation](two-level-validation.md).

### Typed configuration / Options
- `Microsoft.Extensions.Options.ConfigurationExtensions` — section binding.
- `Microsoft.Extensions.Options.DataAnnotations` — `ValidateDataAnnotations()`.
  See [typed-configuration](typed-configuration.md).

### API / OpenAPI
- `Microsoft.AspNetCore.OpenApi` — OpenAPI document generation for Minimal API.
  See [api-layer](api-layer.md).

### Logging (Serilog)
- `Serilog.AspNetCore` — integration + `UseSerilogRequestLogging`.
- `Serilog.Sinks.OpenTelemetry` — exports logs via OTLP.
- Enrichers as needed: `Serilog.Enrichers.Environment`,
  `Serilog.Enrichers.Process`, `Serilog.Enrichers.Thread`.
- (File sink, usually already included in `Serilog.AspNetCore`, for the on-disk
  **fallback**.) See [logging-observability](logging-observability.md).

### Observability (OpenTelemetry)
- `OpenTelemetry.Extensions.Hosting` — host wiring.
- `OpenTelemetry.Exporter.OpenTelemetryProtocol` — OTLP exporter.
- `OpenTelemetry.Instrumentation.AspNetCore`, `.Http`, `.Runtime` — instrumentation.
- `Npgsql.OpenTelemetry` — PostgreSQL provider instrumentation.

### HTTP integration / external services
- `Refit.HttpClientFactory` — typed HTTP clients (Refit) + `AddRefitClient`.
- (`System.IdentityModel.Tokens.Jwt` — only if there is a TokenManager reading JWT expiration.)
  See [external-service-integration](external-service-integration.md).

### Background processing
- `Hangfire.AspNetCore` — job server, dashboard, and DI integration.
- `Hangfire.PostgreSql` — PostgreSQL storage for jobs.
- `OpenTelemetry.Instrumentation.Hangfire` — job traces (at the time of writing, **prerelease/beta**;
  confirm the current version). Goes in the ServiceDefaults. See [background-processing](background-processing.md).

### Resilience / Service discovery
- `Microsoft.Extensions.Http.Resilience` — standard `HttpClient` policies
  (`AddStandardResilienceHandler`, Polly v8). See [external-service-integration](external-service-integration.md).
- `Microsoft.Extensions.ServiceDiscovery` — endpoint resolution.

### Local orchestration (optional)
- `Aspire.Hosting.*` (e.g., `Aspire.Hosting.PostgreSQL`) — spins up dependencies
  (database, etc.) alongside the app in the AppHost. See [AGENTS](../SKILL.md).

### Testing
- `Microsoft.NET.Test.Sdk`, `xunit`, `xunit.runner.visualstudio` — runner/SDK.
- `Microsoft.AspNetCore.Mvc.Testing` — `WebApplicationFactory` for integration tests.
- `Testcontainers.PostgreSql` — real ephemeral database in a container.
- `Respawn` — fast data reset between tests.
- `Shouldly` — **free** fluent asserts (FluentAssertions became paid as of v8+).
- `NSubstitute` — mocks/fakes. See [testing-strategy](testing-strategy.md).

## Principles

- **Always current versions**, confirmed via Context7 / Microsoft Learn.
- **CPM**: version in the central file; `.csproj` without versions.
- **Minimalism**: add a package only when it will actually be used — no speculative
  dependencies.
- **Modern C# syntax** when it improves clarity/maintainability.
