---
tags: [architecture, dotnet, moc, blueprint]
aliases: [Architecture MOC, Vault Map]
---
# 🗺️ .NET Architecture Blueprint

> Central map (MOC) of this vault. Documents an **agnostic architectural pattern**
> for any .NET backend. Copy this folder into the skeleton of new projects.

> 🤖 **AI agent?** Start with [AGENTS](../SKILL.md) (how to act); come back here to navigate.
> 🌐 **API endpoints:** API (index of the HTTP surface — *what* the app exposes).

## Philosophy

**Pragmatic** architecture, focused on clarity and maintainability — no
unnecessary sophistication. The pillars:

- **Clean Architecture in 4 layers** — dependencies always point inward.
- **No MediatR** — use cases are simple [UseCase](application-layer.md) classes
  injected via DI. Less ceremony, less indirection.
- **[Result pattern](result-pattern.md)** — business flow is controlled by
  `Result<T>`/`Error`, **never** by exceptions.
- **[Two-level validation](two-level-validation.md)** — FluentValidation for
  format/input; `DomainException` for domain invariants.
- **[Typed configuration](typed-configuration.md)** — `Options` with DataAnnotations
  and `ValidateOnStart()`: the application fails at boot if the config is invalid.
- **[Self-registered endpoints](api-layer.md)** — each route is an `IEndpoint`
  class discovered via assembly scanning. Zero manual route registration.

## Dependency flow

```
        ┌─────────────────────────────────────────┐
        │                   Api                    │  Minimal API, IEndpoint,
        │           (composition root)             │  ExceptionHandler
        └───────────────┬─────────────────────────┘
                        │ depends on
                        ▼
        ┌─────────────────────────────────────────┐
        │              Application                 │  UseCases, Validators,
        │   (IApplicationDbContext, Options)       │  abstractions
        └───────────────┬─────────────────────────┘
                        │ depends on
                        ▼
        ┌─────────────────────────────────────────┐
        │                Domain                    │  Entities, Value Objects,
        │       (no external dependencies)         │  Result/Error, Entity base
        └─────────────────────────────────────────┘
                        ▲
                        │ implements Application abstractions
                        │ and depends on Domain
        ┌───────────────┴─────────────────────────┐
        │                 Infra                    │  EF Core, persistence,
        │   (implements IApplicationDbContext)     │  external services
        └─────────────────────────────────────────┘
```

**Golden rule of dependencies:**
- `Api → Application → Domain`
- `Infra → Application` (implements abstractions) `+ Infra → Domain`
- `Domain` **references nothing**.
- The `Api` is the composition root: it references `Application` and `Infra` to wire up DI.

## Navigation

> Each note's folder indicates its nature: `layers/`, `patterns/`, `practices/`,
> `reference/`, `guides/`. (Wikilinks resolve by name, regardless of folder.)

### 🧱 Layers (`layers/`)
- [domain-layer](domain-layer.md) — entities, value objects, `Entity` base, `Result`/`Error`.
- [application-layer](application-layer.md) — UseCases, validators, `IApplicationDbContext`, options.
- [infra-layer](infra-layer.md) — EF Core, configurations, migrations, external services.
- [api-layer](api-layer.md) — Minimal API, `IEndpoint`, exception handling.

### 🎯 Architecture patterns (`patterns/`)
- [result-pattern](result-pattern.md) — flow control without exceptions.
- [two-level-validation](two-level-validation.md) — FluentValidation vs DomainException.
- [typed-configuration](typed-configuration.md) — Options validated at boot.

### 🛠️ Cross-cutting practices (`practices/`)
- [logging-observability](logging-observability.md) — Serilog via appsettings, OTLP + file fallback.
- [testing-strategy](testing-strategy.md) — domain unit tests + UseCase integration tests with TestContainers.
- [external-service-integration](external-service-integration.md) — Refit + ACL + resilience + TokenManager for external APIs.
- [authentication-and-security](authentication-and-security.md) — API Key (explicit per-endpoint authorization) + overview (JWT, EF Identity).
- [background-processing](background-processing.md) — background jobs with Hangfire (Job ≠ UseCase).

### 📚 Reference (`reference/`)
- [stack-and-dependencies](stack-and-dependencies.md) — base packages and how to keep versions/syntax current (Context7 / MS Learn).
- [conventions-and-naming](conventions-and-naming.md) — cheat sheet: suffixes, folder structure, routes, visibility.

### 📘 Actionable guides (`guides/`)
- [how-to-add-endpoint](how-to-add-endpoint.md) — add a new route from scratch.
- [how-to-add-usecase](how-to-add-usecase.md) — add a new use case from scratch.

### 🤖 For agents
- [AGENTS](../SKILL.md) — entry point: how to act, implementation order, and scaffolding checklist.

## General conventions

- **Language:** domain, classes, messages, and logs in the **team's ubiquitous
  language** (this skill's examples use English; follow the user's/codebase's
  language when it differs). See [conventions-and-naming](conventions-and-naming.md).
- **Packages:** centralized versions (Central Package Management).
- **Global defaults:** `TargetFramework`, `Nullable`, `ImplicitUsings` in
  `Directory.Build.props` — never redefine per project.
