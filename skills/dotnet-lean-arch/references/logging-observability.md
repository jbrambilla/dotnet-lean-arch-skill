---
tags: [architecture, dotnet, pattern, logging, observability, serilog, opentelemetry]
aliases: [Logging and Observability, Serilog, Observability]
---

# 📊 Logging and Observability

> **Serilog configured via `appsettings.json`**, with `Program.cs` wrapped in
> try/catch/finally and a **bootstrap logger** that guarantees logging from the
> very first moment. Telemetry goes out via **OTLP/OpenTelemetry**; a **file sink
> (txt)** acts as a local **fallback** in case delivery to the provider fails.

See also: [index](index.md) · [api-layer](api-layer.md) · [stack-and-dependencies](stack-and-dependencies.md) · [AGENTS](../SKILL.md)

## Design principles

- **Declarative config:** sinks, levels, and enrichers live in `appsettings.json`
  (`ReadFrom.Configuration`), not hardcoded. Changing destination/level requires no recompile.
- **Never lose the "why" of a boot failure:** the entire `Program.cs` sits inside
  try/catch — if the app fails to start, the reason is logged as `Fatal`.
- **Defense in depth for logging:** the primary destination is OTLP (the
  observability provider); the **file sink is the safety net** if OTLP is
  unavailable, guaranteeing a trail on disk.

## `Program.cs` — bootstrap logger + try/catch/finally

The **bootstrap logger** records events before the DI container exists
(configuration failures, for example). Then the "real" Serilog is built from
configuration (see [ServiceDefaults](#servicedefaults)).

```csharp
using Serilog;
using Serilog.Events;

// 1. Bootstrap logger: covers the window before the host is ready.
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

Log.Information("Starting application...");

try
{
    var builder = WebApplication.CreateBuilder(args);

    builder.AddServiceDefaults();          // configures the "real" Serilog (see below)
    builder.Services.AddOpenApi();
    builder.Services.AddExceptionHandlers();
    // ... AddApplication / AddInfrastructure / AddEndpoints

    var app = builder.Build();

    // 2. Serilog request logging, with noise filtering and enrichment.
    app.UseSerilogRequestLogging(options =>
    {
        options.GetLevel = (httpContext, elapsed, ex) =>
        {
            if (ShouldIgnore(httpContext.Request.Path))      // health, openapi, scans...
                return LogEventLevel.Verbose;
            if (ex is not null || httpContext.Response.StatusCode >= 500)
                return LogEventLevel.Error;
            if (httpContext.Response.StatusCode >= 400)
                return LogEventLevel.Warning;
            if (elapsed > 5000)
                return LogEventLevel.Warning;               // slow requests
            return LogEventLevel.Information;
        };

        options.EnrichDiagnosticContext = (ctx, http) =>
        {
            ctx.Set("RequestHost", http.Request.Host.Value ?? string.Empty);
            ctx.Set("RequestScheme", http.Request.Scheme);
        };
    });

    app.UseExceptionHandler();
    app.MapDefaultEndpoints();   // /health, /alive
    app.MapEndpoints();
    app.Run();
}
catch (Exception ex)
{
    // 3. Boot failure becomes Fatal — it does not vanish silently.
    Log.Fatal(ex, "Application failed to start");
}
finally
{
    // 4. Ensures sinks are flushed (important for buffered sinks, such as OTLP/file).
    Log.CloseAndFlush();
}
```

> `ShouldIgnore(path)` is a helper that filters logging noise (health checks,
> OpenAPI document, favicons, scanner probes). Keep it as an observability
> constant in the Api layer. See [api-layer](api-layer.md).

## `appsettings.json` — declarative configuration

Sinks, levels, and enrichers in the file. **Illustrative** structure (adjust
values to your environment):

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.Hosting.Lifetime": "Information"
      }
    },
    "WriteTo": [
      { "Name": "Console" },
      { "Name": "OpenTelemetry" },
      {
        "Name": "File",
        "Args": {
          "path": "logs/log-.txt",
          "rollingInterval": "Day",
          "retainedFileCountLimit": 7,
          "fileSizeLimitBytes": 10485760,
          "rollOnFileSizeLimit": true,
          "restrictedToMinimumLevel": "Error",
          "outputTemplate": "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] [{SourceContext}] {Message:lj}{NewLine}{Properties}{NewLine}{Exception}"
        }
      }
    ],
    "Enrich": [ "FromLogContext", "WithMachineName", "WithThreadId", "WithProcessId" ]
  }
}
```

### Sink anatomy

| Sink | Role | Note |
| ---- | ----- | ---------- |
| **Console** | Visible in dev/containers | always present |
| **OpenTelemetry** (OTLP) | **Primary destination** | ships to the observability provider |
| **File** (txt) | Local **fallback** | `restrictedToMinimumLevel: Error` + daily and size-based rolling, with retention |

> The file sink intentionally records **only high levels** (e.g., `Error`) — it
> is a safety net, not the main channel. That way, if OTLP fails to deliver,
> errors remain traceable on disk without bloating local storage.

## ServiceDefaults

The "real" Serilog and OpenTelemetry configuration is centralized in the
**ServiceDefaults** project (shared by all services), exposed via
`AddServiceDefaults()`. See the checklist in [AGENTS](../SKILL.md).

```csharp
public static TBuilder ConfigureObservability<TBuilder>(this TBuilder builder)
    where TBuilder : IHostApplicationBuilder
{
    // Serilog takes over the logging pipeline, reading from appsettings.json.
    builder.Logging.ClearProviders();
    builder.Services.AddSerilog((services, config) =>
        config.ReadFrom.Configuration(builder.Configuration));

    // OpenTelemetry: instrumented metrics and tracing.
    builder.Services.AddOpenTelemetry()
        .WithMetrics(m => m
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddRuntimeInstrumentation())
        .WithTracing(t => t
            .AddAspNetCoreInstrumentation(o =>
                o.Filter = ctx => !ShouldIgnore(ctx.Request.Path))  // excludes health checks
            .AddHttpClientInstrumentation()
            // Background jobs join the same trace (see [background-processing](background-processing.md)).
            .AddHangfireInstrumentation(o =>
            {
                o.RecordException = true;
                o.DisplayNameFunc = ctx => $"Job: {ctx.Job.Type.Name}.{ctx.Job.Method.Name}";
            }));

    // OTLP exporter only when the endpoint is configured.
    if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
        builder.Services.AddOpenTelemetry().UseOtlpExporter();

    return builder;
}
```

> **Separation of roles:** **Serilog** handles **logs**; **OpenTelemetry**
> handles **metrics and tracing**. Serilog logs still flow out via OTLP thanks
> to `Serilog.Sinks.OpenTelemetry` — so everything converges on the same provider.

> **`AddHangfireInstrumentation`** comes from `OpenTelemetry.Instrumentation.Hangfire`
> (at the time of writing, in **prerelease/beta** — confirm the stable version via
> Context7 / NuGet). Include it only if the service uses background jobs; with it,
> each job execution becomes a **span** in the same trace as the request that
> enqueued it (thanks to the propagated correlation id — see
> [background-processing](background-processing.md)).

## Health checks

The ServiceDefaults also expose health checks (`/health` for readiness, `/alive`
for liveness), mapped by `MapDefaultEndpoints()`. These paths are included in the
noise filter for both request logging and tracing.

## Principles

- **Serilog via `appsettings.json`** — declarative sinks/levels, no recompiling.
- **`Program.cs` in try/catch/finally** — boot failure becomes `Fatal`; `CloseAndFlush`
  in the `finally`.
- **OTLP as primary, file sink (txt) as fallback** restricted to errors.
- **Filter noise** (health/openapi/scans) in both request logging and tracing.
- **Confirm the current config/syntax** of Serilog and OpenTelemetry via Context7 /
  Microsoft Learn — see [stack-and-dependencies](stack-and-dependencies.md).
