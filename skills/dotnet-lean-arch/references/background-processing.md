---
tags: [architecture, dotnet, pattern, background-jobs, hangfire, async]
aliases: [Background Processing, Background Jobs, Hangfire, Jobs]
---

# ⏱️ Background Processing

> Asynchronous work outside the cycle of an HTTP request, with **Hangfire**. The
> central rule: **Job ≠ UseCase**. Hangfire stays **isolated in Infra** behind an
> abstraction — neither the UseCase nor the Job knows about Hangfire.

See also: [index](index.md) · [application-layer](application-layer.md) · [infra-layer](infra-layer.md) · [result-pattern](result-pattern.md) · [logging-observability](logging-observability.md) · [testing-strategy](testing-strategy.md)

## Job ≠ UseCase

They are things with a **different lifecycle** — treating one as the other forces a
wrong contract:

| | UseCase | Job |
| - | ------- | --- |
| Trigger | HTTP request | enqueueing (now/scheduled/recurring) |
| Input | validated `Request` | **serialized** arguments (simple types) |
| Return | `Result<T>` to the endpoint | nothing — success/failure via **log + retry** |
| Validation | yes (FluentValidation) | no (the enqueuer already validated) |

**Typical flow:** the UseCase validates, **enqueues a Job** and returns quickly (e.g. a
`batchId`); the Job runs the heavy work in the background.

## When to use
- Long-running work that must not hold up the response (batch processing, file generation).
- Recurring tasks (cleanup, reconciliation).
- Resilient retrying of operations that may fail transiently.

## Packages

Confirm the versions and the current API via Context7 / Microsoft Learn (see
[stack-and-dependencies](stack-and-dependencies.md)) — the storage configuration changes between versions.

```
Hangfire.AspNetCore     # server + dashboard + DI integration
Hangfire.PostgreSql     # PostgreSQL storage (consistent with the stack)
```

---

## Abstraction (Application)

Hangfire does **not leak** into Application. UseCases depend on
`IBackgroundJobService` — mockable in tests (see [testing-strategy](testing-strategy.md)).

```csharp
using System.Linq.Expressions;

namespace Blueprint.Application.Abstractions;

public interface IBackgroundJobService
{
    // Job methods are async → Func<T, Task>. Enqueue returns the id (useful for tracking).
    string Enqueue<T>(Expression<Func<T, Task>> methodCall);
    void AddRecurringJob<T>(string jobId, Expression<Func<T, Task>> methodCall, string cronExpression);
    // Extend as needed (Schedule with delay, ContinueWith, ...).
}
```

## The Job (Application, in the enqueuer's slice)

The Job is a **concrete class** with the `Job` suffix, **no interface** and **no
Hangfire attributes** — it is an orchestration POCO. It lives **next to the UseCase** that
enqueues it (narrative cohesion). It does not return `Result`: it executes and **logs** the failure.

```
Application/Features/Widgets/ProcessBatch/
├── ProcessWidgetBatchUseCase.cs     ← validates and enqueues
└── ProcessWidgetJob.cs              ← the background work
Application/Features/Widgets/Shared/
└── ProcessWidgetService.cs          ← ONLY if the logic is reused (see below)
```

```csharp
using Microsoft.Extensions.Logging;

namespace Blueprint.Application.Features.Widgets.ProcessBatch;

public sealed class ProcessWidgetJob(
    ProcessWidgetService service,             // or gateway/IApplicationDbContext directly
    ILogger<ProcessWidgetJob> logger)
{
    public async Task Execute(Guid batchId, Guid widgetId)   // simple, serializable args
    {
        var result = await service.Process(widgetId);

        if (result.IsFailure)
            logger.LogWarning("Failed to process Widget {WidgetId} from batch {BatchId}: {Error}",
                widgetId, batchId, result.Error!.Message);
        // Success/failure are observed via log; exceptions trigger Hangfire's retry.
    }
}
```

## The UseCase (enqueues and returns quickly)

```csharp
using Blueprint.Application.Abstractions;
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Features.Widgets.ProcessBatch;

public sealed class ProcessWidgetBatchUseCase(
    IBackgroundJobService jobs,
    ProcessWidgetBatchValidator validator)
{
    public async Task<Result<Guid>> Execute(ProcessWidgetBatchRequest request, CancellationToken ct)
    {
        var validation = validator.Validate(request);
        if (!validation.IsValid)
            return Error.Validation([.. validation.Errors.Select(e => e.ErrorMessage)]);

        var batchId = Guid.CreateVersion7();

        foreach (var widgetId in request.WidgetIds)
            jobs.Enqueue<ProcessWidgetJob>(job => job.Execute(batchId, widgetId));

        return batchId;   // returns immediately; processing runs in the background
    }
}
```

## Shared service — **only when there is reuse**

Extract an **application Service** only when the **same logic** runs synchronously
(UseCase) **and** in the background (Job). Without reuse, the Job calls the
gateway/`IApplicationDbContext` directly — don't create the layer for nothing.

```csharp
using Microsoft.EntityFrameworkCore;
using Blueprint.Application.Abstractions;
using Blueprint.Application.Abstractions.ExternalServices.Payments;
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Features.Widgets.Shared;

// Context-agnostic: returns Result, consumed by the Job AND by a synchronous UseCase.
public sealed class ProcessWidgetService(IApplicationDbContext db, IPaymentGateway gateway)
{
    public async Task<Result<Widget>> Process(Guid widgetId, CancellationToken ct = default)
    {
        var widget = await db.Widgets.FirstOrDefaultAsync(w => w.Id == widgetId, ct);
        if (widget is null) return Error.NotFound("Widget not found.");

        // ... reused logic ...
        await db.SaveChangesAsync(ct);
        return widget;
    }
}
```

> Note that **Service**, **Job** and **UseCase** do not know about Hangfire — only Infra
> does. This keeps the [application-layer](application-layer.md) testable and portable.

---

## Infra: Hangfire configuration

### Options (validated at boot)

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Infra.BackgroundJobs;

public sealed class BackgroundJobOptions
{
    public const string SectionName = "BackgroundJobs";

    [Required(AllowEmptyStrings = false, ErrorMessage = "The Hangfire connection string is required.")]
    public string HangfireConnection { get; set; } = string.Empty;

    public int WorkerCount { get; set; } = 10;
    public int RetryAttempts { get; set; } = 3;
    public int PollingIntervalSeconds { get; set; } = 2;
    public int JobTimeoutMinutes { get; set; } = 5;

    [Required(AllowEmptyStrings = false, ErrorMessage = "Dashboard login is required.")]
    public string DashboardLogin { get; set; } = string.Empty;
    [Required(AllowEmptyStrings = false, ErrorMessage = "Dashboard password is required.")]
    public string DashboardPassword { get; set; } = string.Empty;
}
```

### Implementation of the abstraction

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

### DI registration

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
                  // The Postgres provider API may vary between versions — confirm via Context7.
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

        // Register each Job so the JobActivator can resolve its dependencies:
        // services.AddScoped<ProcessWidgetJob>();

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

> **`UseFilter`** on the `config` is preferable to mutating `GlobalJobFilters.Filters`
> (static/global) — it avoids filter buildup across runs/tests.

### Filters (observability)

**Correlation id** — propagates the HTTP request id to the job and reinjects it into
the log scope on the server (connects with [logging-observability](logging-observability.md)):

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

**Global exception** — logs the failure (the exception still flows to the retry):

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
            logger.LogError(context.Exception, "Job {JobId} ({JobName}) failed.",
                context.BackgroundJob.Id, context.BackgroundJob.Job.Type.Name);
    }
}
```

### Dashboard with authentication

The `/hangfire` endpoint must be protected. Simple Basic filter (login/password from Options);
the path is already ignored in request logging (see [logging-observability](logging-observability.md)).

```csharp
using System.Text;
using Hangfire.Dashboard;
using Microsoft.AspNetCore.Http;

namespace Blueprint.Infra.BackgroundJobs;

public sealed class DashboardBasicAuthFilter(string login, string password) : IDashboardAuthorizationFilter
{
    public bool Authorize(DashboardContext context)
    {
        var http = context.GetHttpContext();
        var header = http.Request.Headers.Authorization.ToString();

        if (header.StartsWith("Basic ", StringComparison.Ordinal))
        {
            var cred = Encoding.UTF8.GetString(Convert.FromBase64String(header["Basic ".Length..])).Split(':', 2);
            if (cred.Length == 2 && cred[0] == login && cred[1] == password) return true;
        }

        http.Response.StatusCode = StatusCodes.Status401Unauthorized;
        http.Response.Headers.WWWAuthenticate = "Basic realm=\"Hangfire\"";
        return false;
    }
}
```

> In production, also consider restricting `/hangfire` by network/identity
> (in addition to Basic), depending on the topology. See [authentication-and-security](authentication-and-security.md).

### Pipeline (`Program.cs`)

```csharp
// AddInfrastructure already called AddBackgroundJobs (see [infra-layer](infra-layer.md))
app.UseBackgroundJobs();   // mounts the dashboard
```

## Observability (traces) — **mandatory part**

A Job without a trace is a black box: you see it was enqueued, but not what
happened during execution. The implementation **is only complete** when jobs appear
in the application's **OpenTelemetry traces**. With Aspire, the instrumentation goes in
the **ServiceDefaults**, alongside the others (see [logging-observability](logging-observability.md)):

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

- Package: `OpenTelemetry.Instrumentation.Hangfire` (at the time, **prerelease/beta** —
  confirm via Context7 / NuGet).
- Each job execution becomes a **span** with a readable name (`Job: Type.Method`) and
  **recorded exceptions** (`RecordException`).
- Combined with the **correlation id** propagated by `JobCorrelationIdFilter`, the job's
  span links to the **same trace** as the request that enqueued it — end-to-end
  traceability (HTTP → enqueue → execution).

## Recurring jobs

```csharp
jobs.AddRecurringJob<CleanupJob>(
    "daily-cleanup", j => j.Execute(), "0 3 * * *");   // cron: 03:00 every day
```

## Golden rules

- **Idempotency:** a Job **re-executes** on retry (and may run more than once due to a
  visibility failure). Make it safe to repeat (check state before acting).
- **Simple serializable arguments:** pass `Guid`/`string`/`int`. **Never**
  entities or complex objects — Hangfire serializes the arguments.
- **Register the Job in DI** so the `JobActivator` can inject its dependencies.
- **A Job does not return `Result` to anyone:** it handles failure with **log**; exceptions
  trigger the **retry**.

## Principles

- **Job ≠ UseCase** — distinct lifecycle and contract.
- **Hangfire isolated in Infra** behind `IBackgroundJobService`; UseCase/Job/Service
  do not know about it.
- **Concrete Job, `Job` suffix, in the enqueuer's slice**; shared Service
  **only** under UseCase↔Job reuse.
- **Observability (mandatory)**: OTel traces for jobs (`AddHangfireInstrumentation`)
  + propagated correlation id + exception log; `/hangfire` protected and excluded from
  request logging. Without a trace, the implementation is not done.
- **Confirm the current API** of Hangfire/provider via Context7 / Microsoft Learn.
