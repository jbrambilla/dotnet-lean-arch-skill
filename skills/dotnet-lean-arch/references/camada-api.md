---
tags: [arquitetura, dotnet, camada, api, minimal-api, endpoint]
aliases: [Api, Camada de API, Apresentação]
---

# 🟥 Camada Api

> Entrada HTTP via **Minimal API** e **composição da raiz** (monta o DI de todas
> as camadas). Endpoints são auto-registrados via [Padrão `IEndpoint`](#padrão-iendpoint).

Ver também: [index](index.md) · [como-adicionar-endpoint](como-adicionar-endpoint.md) · [result-pattern](result-pattern.md) · [logging-observabilidade](logging-observabilidade.md)

## Padrões e práticas aplicados aqui

- [result-pattern](result-pattern.md) — o endpoint traduz `Result` em resposta HTTP via `.Problem()` (`ResultExtensions`).
- [logging-observabilidade](logging-observabilidade.md) — o `Program.cs` (Serilog + try/catch) e o `GlobalExceptionHandler` são desta camada.
- [convencoes-e-nomenclatura](convencoes-e-nomenclatura.md) — convenção de rotas (`api/v{n}/<recurso>`), tags e visibilidade dos endpoints.
- [autenticacao-e-seguranca](autenticacao-e-seguranca.md) — autenticação (API Key) e autorização explícita por endpoint vivem nesta camada.

## Padrão `IEndpoint`

Cada rota é uma classe `internal sealed` que implementa `IEndpoint`. Um
extension method varre o assembly e registra/mapeia todas — **zero registro
manual de rota**.

### A interface

```csharp
namespace Blueprint.Api.Endpoints;

public interface IEndpoint
{
    void MapEndpoint(IEndpointRouteBuilder app);
}
```

### Um endpoint concreto

```csharp
using Blueprint.Api.Extensions;
using Blueprint.Application.Features.Widgets;

namespace Blueprint.Api.Endpoints.Widgets;

internal sealed class CriarWidget : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app)
    {
        app.MapPost("api/v1/widgets",
            async (CriarWidgetRequest request,
                   CriarWidgetUseCase useCase,
                   CancellationToken cancellationToken) =>
        {
            var response = await useCase.Execute(request, cancellationToken);

            if (response.IsFailure)
                return response.Problem(); // mapeia Error -> ProblemDetails

            return Results.Ok(response.Value);
        })
        .Produces<CriarWidgetResponse>(StatusCodes.Status200OK)
        .WithTags(Tags.Widgets);
    }
}
```

> O endpoint é **fino**: recebe a request, chama o UseCase, traduz o
> [Result](result-pattern.md) em resposta HTTP. Sem lógica de negócio aqui.

### Varredura e mapeamento (`EndpointExtensions`)

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

Constantes centralizadas para agrupar rotas no OpenAPI:

```csharp
namespace Blueprint.Api.Endpoints;

public static class Tags
{
    public const string Widgets = "Widgets";
}
```

## Tradução `Result` → HTTP (`ResultExtensions`)

Centraliza o mapeamento de `ErrorType` para status HTTP via ProblemDetails.
Ver [result-pattern](result-pattern.md).

```csharp
using Blueprint.Domain.Shared;

namespace Blueprint.Api.Extensions;

public static class ResultExtensions
{
    public static IResult Problem(this Result result) => GetProblem(Guard(result.Error));
    public static IResult Problem<T>(this Result<T> result) => GetProblem(Guard(result.Error));

    private static Error Guard(Error? error)
        => error ?? throw new InvalidOperationException(
            "Não é possível retornar problema para um resultado de sucesso.");

    private static IResult GetProblem(Error error)
    {
        if (error.Type == ErrorType.Validation)
            return Results.Problem(
                detail: error.Mensagem,
                statusCode: StatusCodes.Status400BadRequest,
                extensions: new Dictionary<string, object?> { ["errors"] = error.ValidationErrors });

        return Results.Problem(
            detail: error.Mensagem,
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

Rede de segurança para exceções **não previstas** (bugs, falhas de infra). Fluxo
de negócio esperado **não** passa por aqui — usa Result. Devolve um 500 genérico
sem vazar detalhes internos.

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
        logger.LogError(exception, "Ocorreu um erro interno no servidor.");

        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;

        var problem = new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "Erro Interno do Servidor",
            Detail = "Ocorreu um erro inesperado. Tente novamente mais tarde."
        };

        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = problem
        });
    }
}
```

Registro do handler (extension):

```csharp
public static IServiceCollection AddExceptionHandlers(this IServiceCollection services)
{
    services.AddExceptionHandler<GlobalExceptionHandler>();
    services.AddProblemDetails();
    return services;
}
```

## Composição da raiz (`Program.cs`)

A Api junta tudo: ServiceDefaults, OpenAPI, exception handlers, e o DI de cada
camada (`AddApplication`, `AddInfrastructure`), além de varrer os endpoints.

> O `Program.cs` em produção é envolto em **try/catch/finally** com bootstrap
> logger do Serilog (falha de boot vira `Fatal`, `CloseAndFlush` no `finally`) e
> `UseSerilogRequestLogging`. O esqueleto abaixo é simplificado — o padrão
> completo de logging/observabilidade está em [logging-observabilidade](logging-observabilidade.md).

```csharp
using System.Reflection;
using Blueprint.Api.Extensions;
using Blueprint.Application;
using Blueprint.Infra;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();            // OTel, health checks, resiliência (ver bootstrap)
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
    // (opcional) aplicar migrations no startup em dev
}

app.UseHttpsRedirection();
app.MapDefaultEndpoints();   // /health, /alive
app.MapEndpoints();          // varredura de IEndpoint

app.Run();
```

## Princípios

- **Endpoints finos:** request → UseCase → tradução de Result. Nada mais.
- **Auto-registro:** novo `IEndpoint` ⇒ nenhuma mudança no `Program.cs`.
- **Erros previstos via Result/`.Problem()`; imprevistos via GlobalExceptionHandler.**
