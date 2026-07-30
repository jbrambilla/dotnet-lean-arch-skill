---
tags: [architecture, dotnet, guide, usecase, howto]
aliases: [How to Add a UseCase, New UseCase]
---

# 📗 Guide: How to add a UseCase

> Actionable, self-contained step-by-step to create a new use case.

See also: [application-layer](application-layer.md) · [result-pattern](result-pattern.md) · [two-level-validation](two-level-validation.md) · [how-to-add-endpoint](how-to-add-endpoint.md)

## Outcome in one sentence

Create **one file** in `Application/Features/<Resource>/` containing Validator +
UseCase + Request + Response, and register it in `DependencyInjection.cs`.

## Steps

### 1. Create the feature file

`src/<Sln>.Application/Features/<Resource>/<Action>UseCase.cs`. The four types
live together, in this order: **Validator → UseCase → Request → Response**.

### 2. Write the Validator (input level)

FluentValidation, `sealed`. Reuse domain rules when they exist
(e.g., `Email.IsValid`). See [two-level-validation](two-level-validation.md).

```csharp
using FluentValidation;

namespace Blueprint.Application.Features.Widgets;

public sealed class UpdateWidgetValidator : AbstractValidator<UpdateWidgetRequest>
{
    public UpdateWidgetValidator()
    {
        RuleFor(x => x.Id).NotEmpty().WithMessage("The Id is required.");
        RuleFor(x => x.Quantity)
            .GreaterThanOrEqualTo(0).WithMessage("The quantity must not be negative.");
    }
}
```

### 3. Write the UseCase

Primary constructor for injection. Single public method `Execute(request, ct)`
returning [`Result<T>`](result-pattern.md). Typical flow: **log → validate →
query → apply rule → persist → return**.

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Blueprint.Application.Abstractions;
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Features.Widgets;

public sealed class UpdateWidgetUseCase(
    IApplicationDbContext dbContext,
    UpdateWidgetValidator validator,
    ILogger<UpdateWidgetUseCase> logger)
{
    public async Task<Result<UpdateWidgetResponse>> Execute(
        UpdateWidgetRequest request,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("Updating Widget {Id}", request.Id);

        var validation = validator.Validate(request);
        if (!validation.IsValid)
            return Error.Validation([.. validation.Errors.Select(e => e.ErrorMessage)]);

        var widget = await dbContext.Widgets
            .FirstOrDefaultAsync(w => w.Id == request.Id, cancellationToken);

        if (widget is null)
            return Error.NotFound("Widget not found.");

        // The domain rule stays in the entity (it may throw DomainException).
        widget.ChangeQuantity(request.Quantity);

        await dbContext.SaveChangesAsync(cancellationToken);

        return new UpdateWidgetResponse(widget.Id, widget.Quantity);
    }
}
```

### 4. Declare Request and Response (records)

```csharp
public record UpdateWidgetRequest(Guid Id, int Quantity);
public record UpdateWidgetResponse(Guid Id, int Quantity);
```

### 5. Register in DI

In `Application/DependencyInjection.cs`, add the UseCase as **Scoped**. Validators
are already scanned by `AddValidatorsFromAssembly` — they need no
individual registration.

```csharp
services
    .AddScoped<UpdateWidgetUseCase>();
```

### 6. Expose via endpoint

Create the [corresponding endpoint](how-to-add-endpoint.md) that injects this UseCase.

## Quick modeling decisions

- **Query without mutation?** use `.AsNoTracking()`.
- **Resource does not exist?** `Error.NotFound(...)`.
- **Uniqueness/state violation?** `Error.Conflict(...)`.
- **Malformed input?** Validator → `Error.Validation(...)`.
- **Domain invariant?** let the entity throw `DomainException` (do not
  reimplement the rule in the UseCase). See [two-level-validation](two-level-validation.md).

## Checklist

- [ ] One file with Validator + UseCase + Request + Response (in that order).
- [ ] `Execute(request, ct)` returns `Result<T>`.
- [ ] Validates the input and returns `Error.Validation` on failure.
- [ ] Uses `IApplicationDbContext` (never the concrete `DbContext`).
- [ ] Registered as `Scoped` in `DependencyInjection.cs`.
- [ ] No exception used for business flow (see [result-pattern](result-pattern.md)).
