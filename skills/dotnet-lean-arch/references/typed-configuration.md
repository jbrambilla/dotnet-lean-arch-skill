---
tags: [architecture, dotnet, pattern, configuration, options]
aliases: [Typed Configuration, Options Pattern, Options]
---

# ⚙️ Typed Configuration

> Every external configuration becomes a strongly typed `Options` class,
> validated with DataAnnotations and **`ValidateOnStart()`**: if the config is
> invalid, the application **fails at boot** — not at runtime, in the middle of a request.

See also: [index](index.md) · [application-layer](application-layer.md)

## Why

- **Fail-fast:** a configuration error is discovered at startup, not hours later.
- **Typed:** no `IConfiguration["magic:key"]` scattered across the code.
- **Self-documented:** the class + DataAnnotations describe the config contract.

## The Options class

The `SectionName` constant ties the class to the `appsettings.json` section. Declarative
validation via DataAnnotations. It can nest items (with `[ValidateEnumeratedItems]`).

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Application.Features.Widgets;

public sealed class WidgetOptions
{
    public const string SectionName = "Widget";

    [Required(AllowEmptyStrings = false, ErrorMessage = "The base URL is required.")]
    public string BaseUrl { get; set; } = string.Empty;

    [Range(1, int.MaxValue, ErrorMessage = "The limit must be a positive integer.")]
    public int Limit { get; set; }

    [ValidateEnumeratedItems]
    public List<Parameter> Parameters { get; set; } = [];

    public sealed class Parameter
    {
        [Required(AllowEmptyStrings = false, ErrorMessage = "The parameter name is required.")]
        public string Name { get; set; } = string.Empty;

        [Required(AllowEmptyStrings = false, ErrorMessage = "The parameter value is required.")]
        public string Value { get; set; } = string.Empty;
    }
}
```

## Registration with boot-time validation

```csharp
services
    .AddOptions<WidgetOptions>()
    .Bind(configuration.GetSection(WidgetOptions.SectionName))
    .ValidateDataAnnotations()
    // Validations that DataAnnotations cannot cover go in .Validate(...):
    .Validate(o => o.Parameters.Count > 0, "WidgetOptions: at least one parameter is required.")
    .ValidateOnStart();   // <- fails at startup if invalid
```

## Consumption (injection)

Inject `IOptions<T>` into the UseCase or service and read `.Value`:

```csharp
public sealed class DoSomethingUseCase(IOptions<WidgetOptions> options, /* ... */)
{
    public async Task<Result<FooResponse>> Execute(FooRequest request, CancellationToken ct)
    {
        var baseUrl = options.Value.BaseUrl;
        var parameters = options.Value.Parameters;
        // ...
    }
}
```

> For config that changes at runtime, use `IOptionsMonitor<T>`; for the common case
> (read at boot and stable), `IOptions<T>` is enough.

## Corresponding `appsettings.json`

```json
{
  "Widget": {
    "BaseUrl": "https://api.example.internal",
    "Limit": 50,
    "Parameters": [
      { "Name": "foo", "Value": "bar" }
    ]
  }
}
```

## Rules

- **One `Options` class per configurable integration/feature**, with `SectionName`.
- **Always `ValidateDataAnnotations()` + `ValidateOnStart()`** — no silently
  invalid config.
- **Composite rules** (which DataAnnotations cannot express) go in `.Validate(...)`.
- **Secrets do not go into the versioned `appsettings.json`** — use user-secrets in dev
  and the environment's secret provider in production.
