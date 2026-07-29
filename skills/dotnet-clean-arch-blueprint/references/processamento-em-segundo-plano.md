---
tags: [arquitetura, dotnet, pattern, background-jobs, hangfire, async]
aliases: [Processamento em Segundo Plano, Background Jobs, Hangfire, Jobs]
---

# ⏱️ Processamento em Segundo Plano

> Trabalho assíncrono fora do ciclo de uma requisição HTTP, com **Hangfire**. A
> regra central: **Job ≠ UseCase**. O Hangfire fica **isolado na Infra** atrás de
> uma abstração — nem o UseCase nem o Job conhecem o Hangfire.

Ver também: [index](index.md) · [camada-application](camada-application.md) · [camada-infra](camada-infra.md) · [result-pattern](result-pattern.md) · [logging-observabilidade](logging-observabilidade.md) · [estrategia-de-testes](estrategia-de-testes.md)

## Job ≠ UseCase

São coisas com **ciclo de vida diferente** — tratar um como o outro força um
contrato errado:

| | UseCase | Job |
| - | ------- | --- |
| Gatilho | requisição HTTP | enfileiramento (agora/agendado/recorrente) |
| Entrada | `Request` validada | argumentos **serializados** (tipos simples) |
| Retorno | `Result<T>` para o endpoint | nada — sucesso/falha via **log + retry** |
| Validação | sim (FluentValidation) | não (quem enfileirou já validou) |

**Fluxo típico:** o UseCase valida, **enfileira um Job** e retorna rápido (ex.: um
`loteId`); o Job executa o trabalho pesado em background.

## Quando usar
- Trabalho demorado que não deve segurar a resposta (processamento em lote, geração de arquivo).
- Tarefas recorrentes (limpeza, reconciliação).
- Retentativa resiliente de operações que podem falhar de forma transitória.

## Packages

Confirme as versões e a API atual via Context7 / Microsoft Learn (ver
[stack-e-dependencias](stack-e-dependencias.md)) — a configuração do storage muda entre versões.

```
Hangfire.AspNetCore     # servidor + dashboard + integração DI
Hangfire.PostgreSql     # storage PostgreSQL (coerente com o stack)
```

---

## Abstração (Application)

O Hangfire **não vaza** para a Application. Os UseCases dependem de
`IBackgroundJobService` — mockável nos testes (ver [estrategia-de-testes](estrategia-de-testes.md)).

```csharp
using System.Linq.Expressions;

namespace Blueprint.Application.Abstractions;

public interface IBackgroundJobService
{
    // Métodos de Job são async → Func<T, Task>. Enqueue devolve o id (útil p/ rastreio).
    string Enqueue<T>(Expression<Func<T, Task>> methodCall);
    void AddRecurringJob<T>(string jobId, Expression<Func<T, Task>> methodCall, string cronExpression);
    // Estenda conforme a necessidade (Schedule com delay, ContinueWith, ...).
}
```

## O Job (Application, no slice de quem o enfileira)

O Job é uma **classe concreta** com sufixo `Job`, **sem interface** e **sem
atributos do Hangfire** — é um POCO de orquestração. Vive **junto do UseCase** que
o enfileira (coesão narrativa). Não retorna `Result`: executa e **loga** a falha.

```
Application/Features/Widgets/ProcessarLote/
├── ProcessarLoteWidgetsUseCase.cs   ← valida e enfileira
└── ProcessarWidgetJob.cs            ← o trabalho em background
Application/Features/Widgets/Shared/
└── ProcessarWidgetService.cs        ← SÓ se a lógica for reusada (ver abaixo)
```

```csharp
using Microsoft.Extensions.Logging;

namespace Blueprint.Application.Features.Widgets.ProcessarLote;

public sealed class ProcessarWidgetJob(
    ProcessarWidgetService service,           // ou gateway/IApplicationDbContext direto
    ILogger<ProcessarWidgetJob> logger)
{
    public async Task Executar(Guid loteId, Guid widgetId)   // args simples e serializáveis
    {
        var resultado = await service.Processar(widgetId);

        if (resultado.IsFailure)
            logger.LogWarning("Falha ao processar Widget {WidgetId} do lote {LoteId}: {Erro}",
                widgetId, loteId, resultado.Error!.Mensagem);
        // Sucesso/ falha são observados via log; exceções acionam o retry do Hangfire.
    }
}
```

## O UseCase (enfileira e retorna rápido)

```csharp
using Blueprint.Application.Abstractions;
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Features.Widgets.ProcessarLote;

public sealed class ProcessarLoteWidgetsUseCase(
    IBackgroundJobService jobs,
    ProcessarLoteWidgetsValidator validator)
{
    public async Task<Result<Guid>> Execute(ProcessarLoteWidgetsRequest request, CancellationToken ct)
    {
        var validation = validator.Validate(request);
        if (!validation.IsValid)
            return Error.Validation([.. validation.Errors.Select(e => e.ErrorMessage)]);

        var loteId = Guid.CreateVersion7();

        foreach (var widgetId in request.WidgetIds)
            jobs.Enqueue<ProcessarWidgetJob>(job => job.Executar(loteId, widgetId));

        return loteId;   // retorna já; o processamento corre em background
    }
}
```

## Service compartilhado — **só quando há reuso**

Extraia um **Service de aplicação** apenas quando a **mesma lógica** roda de forma
síncrona (UseCase) **e** em background (Job). Sem reuso, o Job chama o
gateway/`IApplicationDbContext` direto — não crie a camada à toa.

```csharp
using Microsoft.EntityFrameworkCore;
using Blueprint.Application.Abstractions;
using Blueprint.Application.Abstractions.ExternalServices.Pagamentos;
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Features.Widgets.Shared;

// Agnóstico de contexto: retorna Result, consumido pelo Job E por um UseCase síncrono.
public sealed class ProcessarWidgetService(IApplicationDbContext db, IPagamentoGateway gateway)
{
    public async Task<Result<Widget>> Processar(Guid widgetId, CancellationToken ct = default)
    {
        var widget = await db.Widgets.FirstOrDefaultAsync(w => w.Id == widgetId, ct);
        if (widget is null) return Error.NotFound("Widget não encontrado.");

        // ... lógica reaproveitada ...
        await db.SaveChangesAsync(ct);
        return widget;
    }
}
```

> Note que **Service**, **Job** e **UseCase** não conhecem o Hangfire — só a Infra
> conhece. Isso mantém a [camada-application](camada-application.md) testável e portável.

---

## Infra: configuração do Hangfire

### Options (validadas no boot)

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Infra.BackgroundJobs;

public sealed class BackgroundJobOptions
{
    public const string SectionName = "BackgroundJobs";

    [Required(AllowEmptyStrings = false, ErrorMessage = "A connection string do Hangfire é obrigatória.")]
    public string HangfireConnection { get; set; } = string.Empty;

    public int WorkerCount { get; set; } = 10;
    public int RetryAttempts { get; set; } = 3;
    public int PollingIntervalSeconds { get; set; } = 2;
    public int JobTimeoutMinutes { get; set; } = 5;

    [Required(AllowEmptyStrings = false, ErrorMessage = "Login do dashboard é obrigatório.")]
    public string DashboardLogin { get; set; } = string.Empty;
    [Required(AllowEmptyStrings = false, ErrorMessage = "Senha do dashboard é obrigatória.")]
    public string DashboardPassword { get; set; } = string.Empty;
}
```

### Implementação da abstração

```csharp
using System.Linq.Expressions;
using Hangfire;
using Blueprint.Application.Abstractions;

namespace Blueprint.Infra.BackgroundJobs;

internal sealed class HangfireJobService : IBackgroundJobService
{
    public string Enqueue<T>(Expression<Func<T, Task>> methodCall)
        => BackgroundJob.Enqueue(methodCall);

    public void AddRecurringJob<T>(string jobId, Expression<Func<T, Task>> methodCall, string cronExpression)
        => RecurringJob.AddOrUpdate(jobId, methodCall, cronExpression);
}
```

### Registro no DI

```csharp
using Hangfire;
using Hangfire.PostgreSql;
using Microsoft.Extensions.Options;

namespace Blueprint.Infra.BackgroundJobs;

public static class DependencyInjection
{
    public static IServiceCollection AddBackgroundJobs(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<BackgroundJobOptions>()
            .Bind(configuration.GetSection(BackgroundJobOptions.SectionName))
            .PostConfigure(o => o.HangfireConnection =
                configuration.GetConnectionString("HangfireConnection") ?? o.HangfireConnection)
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddSingleton<JobCorrelationIdFilter>();
        services.AddSingleton<JobExceptionFilter>();

        services.AddHangfire((provider, config) =>
        {
            var o = provider.GetRequiredService<IOptions<BackgroundJobOptions>>().Value;

            config.SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
                  .UseSimpleAssemblyNameTypeSerializer()
                  .UseRecommendedSerializerSettings()
                  // API do provider Postgres pode variar entre versões — confirme via Context7.
                  .UsePostgreSqlStorage(
                      c => c.UseNpgsqlConnection(o.HangfireConnection),
                      new PostgreSqlStorageOptions
                      {
                          QueuePollInterval = TimeSpan.FromSeconds(o.PollingIntervalSeconds),
                          InvisibilityTimeout = TimeSpan.FromMinutes(o.JobTimeoutMinutes),
                          DistributedLockTimeout = TimeSpan.FromMinutes(1),
                          PrepareSchemaIfNecessary = true,
                          SchemaName = "hangfire"
                      });

            config.UseFilter(new AutomaticRetryAttribute
            {
                Attempts = o.RetryAttempts,
                OnAttemptsExceeded = AttemptsExceededAction.Fail
            });
            config.UseFilter(provider.GetRequiredService<JobCorrelationIdFilter>());
            config.UseFilter(provider.GetRequiredService<JobExceptionFilter>());
        });

        services.AddHangfireServer((sp, opts) =>
            opts.WorkerCount = sp.GetRequiredService<IOptions<BackgroundJobOptions>>().Value.WorkerCount);

        services.AddScoped<IBackgroundJobService, HangfireJobService>();

        // Registre cada Job para o JobActivator resolver suas dependências:
        // services.AddScoped<ProcessarWidgetJob>();

        return services;
    }

    public static IApplicationBuilder UseBackgroundJobs(this IApplicationBuilder app)
    {
        var o = app.ApplicationServices.GetRequiredService<IOptions<BackgroundJobOptions>>().Value;
        app.UseHangfireDashboard("/hangfire", new DashboardOptions
        {
            Authorization = [new DashboardBasicAuthFilter(o.DashboardLogin, o.DashboardPassword)]
        });
        return app;
    }
}
```

> **`UseFilter`** no `config` é preferível a mutar `GlobalJobFilters.Filters`
> (estático/global) — evita acúmulo de filtros entre execuções/testes.

### Filtros (observabilidade)

**Correlation id** — propaga o id da requisição HTTP para o job e o reinjeta no
escopo de log no servidor (conecta com [logging-observabilidade](logging-observabilidade.md)):

```csharp
using Hangfire.Client;
using Hangfire.Common;
using Hangfire.Server;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace Blueprint.Infra.BackgroundJobs;

public sealed class JobCorrelationIdFilter(
    IHttpContextAccessor accessor,
    ILogger<JobCorrelationIdFilter> logger) : JobFilterAttribute, IClientFilter, IServerFilter
{
    private const string Key = "CorrelationId";
    private static readonly AsyncLocal<string?> _current = new();

    public void OnCreating(CreatingContext context)
        => context.SetJobParameter(Key,
            accessor.HttpContext?.Request.Headers["Correlation-Id"].FirstOrDefault()
            ?? accessor.HttpContext?.TraceIdentifier
            ?? _current.Value
            ?? Guid.NewGuid().ToString());

    public void OnCreated(CreatedContext context) { }

    public void OnPerforming(PerformingContext context)
    {
        var id = context.GetJobParameter<string>(Key);
        if (string.IsNullOrEmpty(id)) return;
        _current.Value = id;
        context.Items["LoggerScope"] = logger.BeginScope(
            new Dictionary<string, object> { [Key] = id });
    }

    public void OnPerformed(PerformedContext context)
    {
        _current.Value = null;
        if (context.Items.TryGetValue("LoggerScope", out var s) && s is IDisposable d) d.Dispose();
    }
}
```

**Exceção global** — loga a falha (a exceção segue para o retry):

```csharp
using Hangfire.Common;
using Hangfire.Server;
using Microsoft.Extensions.Logging;

namespace Blueprint.Infra.BackgroundJobs;

public sealed class JobExceptionFilter(ILogger<JobExceptionFilter> logger)
    : JobFilterAttribute, IServerFilter
{
    public void OnPerforming(PerformingContext context) { }

    public void OnPerformed(PerformedContext context)
    {
        if (context.Exception is not null)
            logger.LogError(context.Exception, "Job {JobId} ({JobName}) falhou.",
                context.BackgroundJob.Id, context.BackgroundJob.Job.Type.Name);
    }
}
```

### Dashboard com autenticação

O `/hangfire` deve ser protegido. Filtro Basic simples (login/senha das Options);
o path já é ignorado no request logging (ver [logging-observabilidade](logging-observabilidade.md)).

```csharp
using System.Text;
using Hangfire.Dashboard;
using Microsoft.AspNetCore.Http;

namespace Blueprint.Infra.BackgroundJobs;

public sealed class DashboardBasicAuthFilter(string login, string senha) : IDashboardAuthorizationFilter
{
    public bool Authorize(DashboardContext context)
    {
        var http = context.GetHttpContext();
        var header = http.Request.Headers.Authorization.ToString();

        if (header.StartsWith("Basic ", StringComparison.Ordinal))
        {
            var cred = Encoding.UTF8.GetString(Convert.FromBase64String(header["Basic ".Length..])).Split(':', 2);
            if (cred.Length == 2 && cred[0] == login && cred[1] == senha) return true;
        }

        http.Response.StatusCode = StatusCodes.Status401Unauthorized;
        http.Response.Headers.WWWAuthenticate = "Basic realm=\"Hangfire\"";
        return false;
    }
}
```

> Em produção, considere também restringir o `/hangfire` por rede/identidade
> (além do Basic), conforme a topologia. Ver [autenticacao-e-seguranca](autenticacao-e-seguranca.md).

### Pipeline (`Program.cs`)

```csharp
// AddInfrastructure já chamou AddBackgroundJobs (ver [camada-infra](camada-infra.md))
app.UseBackgroundJobs();   // monta o dashboard
```

## Observabilidade (traces) — **parte obrigatória**

Um Job sem trace é uma caixa-preta: você vê que foi enfileirado, mas não o que
aconteceu na execução. A implementação **só está completa** quando os jobs entram
nos **traces OpenTelemetry** da aplicação. Com Aspire, a instrumentação vai nos
**ServiceDefaults**, junto das demais (ver [logging-observabilidade](logging-observabilidade.md)):

```csharp
.WithTracing(t => t
    .AddAspNetCoreInstrumentation(/* ... */)
    .AddHttpClientInstrumentation()
    .AddHangfireInstrumentation(o =>
    {
        o.RecordException = true;
        o.DisplayNameFunc = ctx => $"Job: {ctx.Job.Type.Name}.{ctx.Job.Method.Name}";
    }));
```

- Pacote: `OpenTelemetry.Instrumentation.Hangfire` (à época, **prerelease/beta** —
  confirme via Context7 / NuGet).
- Cada execução de job vira um **span** com nome legível (`Job: Tipo.Método`) e
  **exceções registradas** (`RecordException`).
- Combinado com o **correlation id** propagado pelo `JobCorrelationIdFilter`, o span
  do job se liga ao **mesmo trace** da requisição que o enfileirou — rastreabilidade
  ponta a ponta (HTTP → enqueue → execução).

## Jobs recorrentes

```csharp
jobs.AddRecurringJob<LimpezaJob>(
    "limpeza-diaria", j => j.Executar(), "0 3 * * *");   // cron: 03:00 todo dia
```

## Regras de ouro

- **Idempotência:** um Job **reexecuta** em retry (e pode rodar mais de uma vez por
  falha de visibilidade). Faça-o seguro para repetição (cheque estado antes de agir).
- **Argumentos serializáveis simples:** passe `Guid`/`string`/`int`. **Nunca**
  entidades ou objetos complexos — o Hangfire serializa os argumentos.
- **Registre o Job no DI** para o `JobActivator` injetar suas dependências.
- **Job não retorna `Result` para ninguém:** trata a falha com **log**; exceções
  acionam o **retry**.

## Princípios

- **Job ≠ UseCase** — ciclo de vida e contrato distintos.
- **Hangfire isolado na Infra** atrás de `IBackgroundJobService`; UseCase/Job/Service
  não o conhecem.
- **Job concreto, sufixo `Job`, no slice de quem enfileira**; Service compartilhado
  **só** sob reuso UseCase↔Job.
- **Observabilidade (obrigatória)**: traces OTel dos jobs (`AddHangfireInstrumentation`)
  + correlation id propagado + log de exceção; `/hangfire` protegido e fora do
  request logging. Sem trace, a implementação não está pronta.
- **Confirme a API atual** do Hangfire/provider via Context7 / Microsoft Learn.
