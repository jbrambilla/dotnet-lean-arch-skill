---
tags: [architecture, dotnet, layer, application, usecase]
aliases: [Application, Application Layer]
---

# 🟩 Application Layer

> Orchestrates the use cases. Depends only on [Domain](domain-layer.md). Defines
> abstractions (`IApplicationDbContext`) that [Infra](infra-layer.md) implements.
> **No MediatR**.

See also: [index](index.md) · [how-to-add-usecase](how-to-add-usecase.md) · [result-pattern](result-pattern.md) · [typed-configuration](typed-configuration.md) · [external-service-integration](external-service-integration.md)

## Patterns and practices applied here

- [result-pattern](result-pattern.md) — UseCases return `Result<T>`.
- [two-level-validation](two-level-validation.md) — **level 1** (FluentValidation in the UseCase) lives here.
- [typed-configuration](typed-configuration.md) — `Options` classes and their registration with `ValidateOnStart`.
- [external-service-integration](external-service-integration.md) — the `IXxxGateway` abstraction (integration contract) is defined here.
- [background-processing](background-processing.md) — UseCases and Jobs (`Job` suffix) live here; enqueueing uses the `IBackgroundJobService` abstraction.

## UseCase pattern

Each use case is a simple class with a single public method
`Execute(request, ct)` that returns [`Result<T>`](result-pattern.md). Injected as
**Scoped** and consumed directly by the endpoint.

### File structure

One file per use case, containing **four types together**, in this order:

1. The `Validator` (FluentValidation) — `sealed`.
2. The `UseCase` class.
3. The `record Request`.
4. The `record Response`.

```csharp
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Blueprint.Application.Abstractions;
using Blueprint.Domain;
using Blueprint.Domain.Shared;
using Blueprint.Domain.ValueObjects;

namespace Blueprint.Application.Features.Widgets;

// 1. Validator — format/input. See [two-level-validation](two-level-validation.md).
public sealed class CreateWidgetValidator : AbstractValidator<CreateWidgetRequest>
{
    public CreateWidgetValidator()
    {
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("The name cannot be empty.")
            .MaximumLength(120).WithMessage("The name must be at most 120 characters.");

        RuleFor(x => x.Contact)
            .NotEmpty().WithMessage("The contact cannot be empty.")
            .Must(Email.IsValid).WithMessage("The provided email is invalid.");

        RuleFor(x => x.Quantity)
            .GreaterThanOrEqualTo(0).WithMessage("The quantity cannot be negative.");
    }
}

// 2. UseCase — orchestration via primary constructor (injection).
public sealed class CreateWidgetUseCase(
    IApplicationDbContext dbContext,
    CreateWidgetValidator validator,
    ILogger<CreateWidgetUseCase> logger)
{
    public async Task<Result<CreateWidgetResponse>> Execute(
        CreateWidgetRequest request,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("Creating Widget: {Name}", request.Name);

        var validationResult = validator.Validate(request);
        if (!validationResult.IsValid)
            return Error.Validation([.. validationResult.Errors.Select(e => e.ErrorMessage)]);

        var alreadyExists = await dbContext.Widgets
            .AsNoTracking()
            .AnyAsync(w => w.Name == request.Name, cancellationToken);

        if (alreadyExists)
            return Error.Conflict("A Widget with this name already exists.");

        // Domain invariants are enforced in the constructor (DomainException).
        var widget = new Widget(request.Contact, request.Name, request.Quantity);

        dbContext.Widgets.Add(widget);
        await dbContext.SaveChangesAsync(cancellationToken);

        logger.LogInformation("Widget created with Id {Id}", widget.Id);

        return new CreateWidgetResponse(widget.Id, widget.Name, widget.Quantity);
    }
}

// 3. Request
public record CreateWidgetRequest(string Name, string Contact, int Quantity);

// 4. Response
public record CreateWidgetResponse(Guid Id, string Name, int Quantity);
```

> **Query reads:** use `.AsNoTracking()` when there is no mutation.

## `IApplicationDbContext` abstraction

The Application **does not know** the concrete `DbContext` — only this interface. This
preserves the dependency rule (Infra implements it, see [infra-layer](infra-layer.md)).

```csharp
using Microsoft.EntityFrameworkCore;
using Blueprint.Domain;

namespace Blueprint.Application.Abstractions;

public interface IApplicationDbContext
{
    DbSet<Widget> Widgets { get; }
    DbSet<Bar> Bars { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

## Typed Options

External configuration becomes a typed class, validated at boot. Details in
[typed-configuration](typed-configuration.md).

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Application.Features.Widgets;

public sealed class WidgetOptions
{
    public const string SectionName = "Widget";

    [Required(AllowEmptyStrings = false)]
    public string BaseUrl { get; set; } = string.Empty;

    [Range(1, int.MaxValue)]
    public int DefaultLimit { get; set; }
}
```

## DI registration (`DependencyInjection.cs`)

UseCases and options are registered **manually** (no auto-discovery here).
Validators are scanned from the assembly.

```csharp
using FluentValidation;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Blueprint.Application.Features.Widgets;

namespace Blueprint.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Typed options validated at boot
        services
            .AddOptions<WidgetOptions>()
            .Bind(configuration.GetSection(WidgetOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();

        // UseCases — Scoped, manual registration
        services
            .AddScoped<CreateWidgetUseCase>();

        // Validators — assembly scanning (includes internal types)
        services
            .AddValidatorsFromAssembly(
                typeof(DependencyInjection).Assembly,
                includeInternalTypes: true);

        return services;
    }
}
```

## Principles

- **One file per use case**, with Validator + UseCase + Request + Response.
- **Always return `Result<T>`** — never throw exceptions for business flow.
- **Do not leak Infra types** — depend on `IApplicationDbContext`, never on the
  concrete `DbContext`.
- **Register UseCases manually** in `DependencyInjection.cs`.
