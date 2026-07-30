---
tags: [architecture, dotnet, layer, api, minimal-api, endpoint]
aliases: [Api, API Layer, Presentation]
---

# 🟥 Api Layer

> HTTP entry point via **Minimal API** and **composition root** (wires up the DI of all
> layers). Endpoints are auto-registered via the [`IEndpoint` pattern](#iendpoint-pattern).

See also: [index](index.md) · [how-to-add-endpoint](how-to-add-endpoint.md) · [result-pattern](result-pattern.md) · [logging-observability](logging-observability.md)

## Patterns and practices applied here

- [result-pattern](result-pattern.md) — the endpoint translates `Result` into an HTTP response via `.Problem()` (`ResultExtensions`).
- [logging-observability](logging-observability.md) — the `Program.cs` (Serilog + try/catch) and the `GlobalExceptionHandler` belong to this layer.
- [conventions-and-naming](conventions-and-naming.md) — route convention (`api/v{n}/<resource>`), tags, and endpoint visibility.
- [authentication-and-security](authentication-and-security.md) — authentication (API Key) and explicit per-endpoint authorization live in this layer.

## `IEndpoint` pattern

Each route is an `internal sealed` class that implements `IEndpoint`. An
extension method scans the assembly and registers/maps them all — **zero manual
route registration**.

### The interface

```csharp
namespace Blueprint.Api.Endpoints;

public interface IEndpoint
{
    void MapEndpoint(IEndpointRouteBuilder app);
}
```

### A concrete endpoint

```csharp
using Blueprint.Api.Extensions;
using Blueprint.Application.Features.Widgets;

namespace Blueprint.Api.Endpoints.Widgets;

internal sealed class CreateWidget : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app)
    {
        app.MapPost("api/v1/widgets",
            async (CreateWidgetRequest request,
                   CreateWidgetUseCase useCase,
                   CancellationToken cancellationToken) =>
        {
            var response = await useCase.Execute(request, cancellationToken);

            if (response.IsFailure)
                return response.Problem(); // maps Error -> ProblemDetails

            return Results.Ok(response.Value);
        })
        .Produces<CreateWidgetResponse>(StatusCodes.Status200OK)
        .WithTags(Tags.Widgets);
    }
}
```

> The endpoint is **thin**: it receives the request, calls the UseCase, and translates the
> [Result](result-pattern.md) into an HTTP response. No business logic here.

### Scanning and mapping (`EndpointExtensions`)

```csharp
using System.Reflection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Blueprint.Api.Endpoints;

namespace Blueprint.Api.Extensions;

public static class EndpointExtensions
{
    public static IServiceCollection AddEndpoints(
        this IServiceCollection services, Assembly assembly)
    {
        ServiceDescriptor[] descriptors = assembly
            .DefinedTypes
            .Where(t => t is { IsAbstract: false, IsInterface: false } &&
                        t.IsAssignableTo(typeof(IEndpoint)))
            .Select(t => ServiceDescriptor.Transient(typeof(IEndpoint), t))
            .ToArray();

        services.TryAddEnumerable(descriptors);
        return services;
    }

    public static IApplicationBuilder MapEndpoints(
        this WebApplication app, RouteGroupBuilder? group = null)
    {
        var endpoints = app.Services.GetRequiredService<IEnumerable<IEndpoint>>();
        IEndpointRouteBuilder builder = group ?? app;

        foreach (var endpoint in endpoints)
            endpoint.MapEndpoint(builder);

        return app;
    }
}
```

### Tags

Centralized constants to group routes in OpenAPI:

```csharp
namespace Blueprint.Api.Endpoints;

public static class Tags
{
    public const string Widgets = "Widgets";
}
```

## `Result` → HTTP translation (`ResultExtensions`)

Centralizes the mapping from `ErrorType` to HTTP status via ProblemDetails.
See [result-pattern](result-pattern.md).

```csharp
using Blueprint.Domain.Shared;

namespace Blueprint.Api.Extensions;

public static class ResultExtensions
{
    public static IResult Problem(this Result result) => GetProblem(Guard(result.Error));
    public static IResult Problem<T>(this Result<T> result) => GetProblem(Guard(result.Error));

    private static Error Guard(Error? error)
        => error ?? throw new InvalidOperationException(
            "Cannot return a problem for a success result.");

    private static IResult GetProblem(Error error)
    {
        if (error.Type == ErrorType.Validation)
            return Results.Problem(
                detail: error.Message,
                statusCode: StatusCodes.Status400BadRequest,
                extensions: new Dictionary<string, object?> { ["errors"] = error.ValidationErrors });

        return Results.Problem(
            detail: error.Message,
            statusCode: error.Type switch
            {
                ErrorType.NotFound => StatusCodes.Status404NotFound,
                ErrorType.Conflict => StatusCodes.Status409Conflict,
                _                  => StatusCodes.Status500InternalServerError
            });
    }
}
```

## GlobalExceptionHandler

Safety net for **unexpected** exceptions (bugs, infrastructure failures). Expected
business flow does **not** go through here — it uses Result. Returns a generic 500
without leaking internal details.

```csharp
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace Blueprint.Api.Handlers;

internal sealed class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger,
    IProblemDetailsService problemDetailsService) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        logger.LogError(exception, "An internal server error occurred.");

        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;

        var problem = new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "Internal Server Error",
            Detail = "An unexpected error occurred. Please try again later."
        };

        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = problem
        });
    }
}
```

Handler registration (extension):

```csharp
public static IServiceCollection AddExceptionHandlers(this IServiceCollection services)
{
    services.AddExceptionHandler<GlobalExceptionHandler>();
    services.AddProblemDetails();
    return services;
}
```

## Composition root (`Program.cs`)

The Api brings everything together: ServiceDefaults, OpenAPI, exception handlers, and
each layer's DI (`AddApplication`, `AddInfrastructure`), plus endpoint scanning.

> The production `Program.cs` is wrapped in **try/catch/finally** with Serilog's
> bootstrap logger (a boot failure becomes `Fatal`, `CloseAndFlush` in the `finally`) and
> `UseSerilogRequestLogging`. The skeleton below is simplified — the complete
> logging/observability pattern is in [logging-observability](logging-observability.md).

```csharp
using System.Reflection;
using Blueprint.Api.Extensions;
using Blueprint.Application;
using Blueprint.Infra;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();            // OTel, health checks, resilience (see bootstrap)
builder.Services.AddOpenApi();
builder.Services.AddExceptionHandlers();

builder.Services
    .AddApplication(builder.Configuration)
    .AddInfrastructure(builder.Configuration);

builder.Services.AddEndpoints(Assembly.GetExecutingAssembly());

var app = builder.Build();

app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    // (optional) apply migrations at startup in dev
}

app.UseHttpsRedirection();
app.MapDefaultEndpoints();   // /health, /alive
app.MapEndpoints();          // IEndpoint scanning

app.Run();
```

## Principles

- **Thin endpoints:** request → UseCase → Result translation. Nothing else.
- **Auto-registration:** a new `IEndpoint` ⇒ no changes to `Program.cs`.
- **Expected errors via Result/`.Problem()`; unexpected ones via GlobalExceptionHandler.**
