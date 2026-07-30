---
tags: [architecture, dotnet, guide, endpoint, howto]
aliases: [How to Add an Endpoint, New Endpoint]
---

# 📘 Guide: How to add an Endpoint

> Actionable, self-contained step-by-step to expose a new HTTP route.
> Prerequisites: the corresponding [UseCase](how-to-add-usecase.md) already
> exists (or will be created).

See also: [api-layer](api-layer.md) · [result-pattern](result-pattern.md) · [how-to-add-usecase](how-to-add-usecase.md) · [authentication-and-security](authentication-and-security.md)

## Outcome in one sentence

Create an `internal sealed : IEndpoint` class in the `Endpoints/` folder. The
auto-registration takes care of the rest — **you do not touch `Program.cs`**.

## Steps

### 1. Create the endpoint file

In `src/<Sln>.Api/Endpoints/<Resource>/<Action>.cs`. Folder-per-resource convention.

### 2. Implement `IEndpoint`

`internal sealed` class. Map the route in `MapEndpoint`, injecting the UseCase and the
`CancellationToken` as handler parameters (resolved by DI).

```csharp
using Blueprint.Api.Extensions;
using Blueprint.Application.Features.Widgets;

namespace Blueprint.Api.Endpoints.Widgets;

internal sealed class GetWidgetById : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app)
    {
        app.MapGet("api/v1/widgets/{id:guid}",
            async (Guid id,
                   GetWidgetByIdUseCase useCase,
                   CancellationToken cancellationToken) =>
        {
            var request = new GetWidgetByIdRequest(id);
            var response = await useCase.Execute(request, cancellationToken);

            if (response.IsFailure)
                return response.Problem();      // 404/400/409/500 according to ErrorType

            return Results.Ok(response.Value);
        })
        .Produces<GetWidgetByIdResponse>(StatusCodes.Status200OK)
        .WithTags(Tags.Widgets)
        .RequireAuthorization();   // protected (see step 5)
    }
}
```

### 3. Translate the result

- **Success:** `Results.Ok(response.Value)` (or `Created`, `NoContent`, etc.).
- **Failure:** `return response.Problem();` — the [result-pattern](result-pattern.md) maps the
  `ErrorType` to the correct HTTP status via `ResultExtensions`.

### 4. Document for OpenAPI

- `.Produces<TResponse>(StatusCodes.Status200OK)` for the success contract.
- `.WithTags(Tags.<Resource>)` for grouping (add the constant to `Tags` if new).

### 5. Declare authorization (always explicit)

There is no `FallbackPolicy` — **every endpoint declares its intent**, for semantics and
clarity. Pick one:

- **Protected** (requires a credential, e.g., `X-Api-Key`):
  ```csharp
  .RequireAuthorization();
  ```
- **Public** (no credential — e.g., health, info, webhooks):
  ```csharp
  .AllowAnonymous();
  ```

> ⚠️ Forgetting to declare leaves the endpoint **open**. Always mark it — and, for
> sensitive routes, ensure with a test that they respond **401** without a credential. Mechanism
> details in [authentication-and-security](authentication-and-security.md).

### 6. Done — no manual registration

When the app starts, `AddEndpoints(assembly)` discovers the class and `MapEndpoints()`
maps it (see [api-layer](api-layer.md)). No change to `Program.cs`.

## Checklist

- [ ] File in `Endpoints/<Resource>/`, class `internal sealed : IEndpoint`.
- [ ] Handler injects the UseCase + `CancellationToken`.
- [ ] Calls `useCase.Execute(...)` and checks `IsFailure` → `.Problem()`.
- [ ] `.Produces<T>(...)` and `.WithTags(...)` configured.
- [ ] **Authorization declared explicitly**: `.RequireAuthorization()` or `.AllowAnonymous()`.
- [ ] **No** business logic in the endpoint (it lives in the UseCase).
- [ ] No edits to `Program.cs` were needed.

## Anti-patterns to avoid

- ❌ Business logic/database queries directly in the handler → move to the UseCase.
- ❌ `try/catch` for business rules → use [Result](result-pattern.md).
- ❌ Registering the route manually in `Program.cs` → auto-registration already does it.
