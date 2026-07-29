---
tags: [arquitetura, dotnet, pattern, logging, observabilidade, serilog, opentelemetry]
aliases: [Logging e Observabilidade, Serilog, Observabilidade]
---

# 📊 Logging e Observabilidade

> **Serilog configurado via `appsettings.json`**, com `Program.cs` envolto em
> try/catch/finally e um **bootstrap logger** que garante log desde o primeiro
> instante. A telemetria sai via **OTLP/OpenTelemetry**; um **file sink (txt)**
> serve de **fallback** local caso a entrega ao provedor falhe.

Ver também: [index](index.md) · [camada-api](camada-api.md) · [stack-e-dependencias](stack-e-dependencias.md) · [AGENTS](../SKILL.md)

## Princípios de design

- **Config declarativa:** os sinks, níveis e enrichers vivem no `appsettings.json`
  (`ReadFrom.Configuration`), não hardcoded. Trocar destino/nível não recompila.
- **Nunca perder o "porquê" da falha de boot:** o `Program.cs` inteiro fica em
  try/catch — se a app não sobe, o motivo é logado como `Fatal`.
- **Defesa em profundidade no log:** o destino primário é o OTLP (provedor de
  observabilidade); o **file sink é a rede de segurança** se o OTLP estiver
  indisponível, garantindo rastro em disco.

## `Program.cs` — bootstrap logger + try/catch/finally

O **bootstrap logger** registra eventos antes do container de DI existir (falhas
de configuração, por exemplo). Depois o Serilog "real" é montado a partir da
configuração (ver [ServiceDefaults](#servicedefaults)).

```csharp
using Serilog;
using Serilog.Events;

// 1. Bootstrap logger: cobre o intervalo antes do host estar pronto.
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

Log.Information("Iniciando aplicação...");

try
{
    var builder = WebApplication.CreateBuilder(args);

    builder.AddServiceDefaults();          // configura o Serilog "real" (ver abaixo)
    builder.Services.AddOpenApi();
    builder.Services.AddExceptionHandlers();
    // ... AddApplication / AddInfrastructure / AddEndpoints

    var app = builder.Build();

    // 2. Request logging do Serilog, com filtro de ruído e enriquecimento.
    app.UseSerilogRequestLogging(options =>
    {
        options.GetLevel = (httpContext, elapsed, ex) =>
        {
            if (DeveIgnorar(httpContext.Request.Path))       // health, openapi, scans...
                return LogEventLevel.Verbose;
            if (ex is not null || httpContext.Response.StatusCode >= 500)
                return LogEventLevel.Error;
            if (httpContext.Response.StatusCode >= 400)
                return LogEventLevel.Warning;
            if (elapsed > 5000)
                return LogEventLevel.Warning;               // requisições lentas
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
    // 3. Falha de boot vira Fatal — não some silenciosamente.
    Log.Fatal(ex, "Falha ao iniciar a aplicação");
}
finally
{
    // 4. Garante flush dos sinks (importante para sinks com buffer, como OTLP/file).
    Log.CloseAndFlush();
}
```

> `DeveIgnorar(path)` é um helper que filtra ruído de logging (health checks,
> documento OpenAPI, favicons, varreduras de scanners). Mantenha-o como constante
> de observabilidade na camada Api. Ver [camada-api](camada-api.md).

## `appsettings.json` — configuração declarativa

Sinks, níveis e enrichers no arquivo. Estrutura **ilustrativa** (ajuste valores
ao ambiente):

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

### Anatomia dos sinks

| Sink | Papel | Observação |
| ---- | ----- | ---------- |
| **Console** | Visível em dev/containers | sempre presente |
| **OpenTelemetry** (OTLP) | **Destino primário** | envia ao provedor de observabilidade |
| **File** (txt) | **Fallback** local | `restrictedToMinimumLevel: Error` + rolling diário e por tamanho, com retenção |

> O file sink intencionalmente registra **só níveis altos** (ex.: `Error`) — é
> rede de segurança, não o canal principal. Assim, se o OTLP não entregar, os
> erros ainda ficam rastreáveis em disco sem inflar o armazenamento local.

## ServiceDefaults

A configuração do Serilog "real" e do OpenTelemetry é centralizada no projeto
**ServiceDefaults** (compartilhado por todos os serviços), exposta via
`AddServiceDefaults()`. Ver o checklist em [AGENTS](../SKILL.md).

```csharp
public static TBuilder ConfigureObservability<TBuilder>(this TBuilder builder)
    where TBuilder : IHostApplicationBuilder
{
    // Serilog assume o pipeline de logging, lendo do appsettings.json.
    builder.Logging.ClearProviders();
    builder.Services.AddSerilog((services, config) =>
        config.ReadFrom.Configuration(builder.Configuration));

    // OpenTelemetry: métricas e tracing instrumentados.
    builder.Services.AddOpenTelemetry()
        .WithMetrics(m => m
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddRuntimeInstrumentation())
        .WithTracing(t => t
            .AddAspNetCoreInstrumentation(o =>
                o.Filter = ctx => !DeveIgnorar(ctx.Request.Path))  // exclui health checks
            .AddHttpClientInstrumentation()
            // Background jobs entram no mesmo trace (ver [processamento-em-segundo-plano](processamento-em-segundo-plano.md)).
            .AddHangfireInstrumentation(o =>
            {
                o.RecordException = true;
                o.DisplayNameFunc = ctx => $"Job: {ctx.Job.Type.Name}.{ctx.Job.Method.Name}";
            }));

    // Exporter OTLP só quando o endpoint estiver configurado.
    if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
        builder.Services.AddOpenTelemetry().UseOtlpExporter();

    return builder;
}
```

> **Separação de papéis:** o **Serilog** cuida de **logs**; o **OpenTelemetry**
> cuida de **métricas e tracing**. Os logs do Serilog ainda saem via OTLP graças
> ao `Serilog.Sinks.OpenTelemetry` — então tudo conflui ao mesmo provedor.

> **`AddHangfireInstrumentation`** vem de `OpenTelemetry.Instrumentation.Hangfire`
> (à época, em **prerelease/beta** — confirme a versão estável via Context7 / NuGet).
> Inclua-a só se o serviço usa background jobs; com ela, cada execução de job vira
> um **span** no mesmo trace da requisição que o enfileirou (graças ao correlation
> id propagado — ver [processamento-em-segundo-plano](processamento-em-segundo-plano.md)).

## Health checks

Os ServiceDefaults também expõem health checks (`/health` para readiness, `/alive`
para liveness), mapeados por `MapDefaultEndpoints()`. Esses paths entram no filtro
de ruído do request logging e do tracing.

## Princípios

- **Serilog via `appsettings.json`** — sinks/níveis declarativos, sem recompilar.
- **`Program.cs` em try/catch/finally** — falha de boot vira `Fatal`; `CloseAndFlush`
  no `finally`.
- **OTLP primário, file sink (txt) como fallback** restrito a erros.
- **Filtre ruído** (health/openapi/scans) tanto no request logging quanto no tracing.
- **Confirme a config/sintaxe atual** do Serilog e OpenTelemetry via Context7 /
  Microsoft Learn — ver [stack-e-dependencias](stack-e-dependencias.md).
