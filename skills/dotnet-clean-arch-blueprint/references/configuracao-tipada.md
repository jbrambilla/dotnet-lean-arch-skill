---
tags: [arquitetura, dotnet, pattern, configuracao, options]
aliases: [Configuração Tipada, Options Pattern, Options]
---

# ⚙️ Configuração Tipada

> Toda configuração externa vira uma classe `Options` fortemente tipada,
> validada com DataAnnotations e **`ValidateOnStart()`**: se a config estiver
> inválida, a aplicação **falha no boot** — não em runtime, no meio de um request.

Ver também: [index](index.md) · [camada-application](camada-application.md)

## Por quê

- **Fail-fast:** erro de configuração é descoberto no startup, não horas depois.
- **Tipado:** sem `IConfiguration["chave:magica"]` espalhado pelo código.
- **Autodocumentado:** a classe + DataAnnotations descrevem o contrato da config.

## A classe de Options

`SectionName` constante amarra a classe à seção do `appsettings.json`. Validação
declarativa via DataAnnotations. Pode aninhar itens (com `[ValidateEnumeratedItems]`).

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Application.Features.Widgets;

public sealed class WidgetOptions
{
    public const string SectionName = "Widget";

    [Required(AllowEmptyStrings = false, ErrorMessage = "A URL base é obrigatória.")]
    public string BaseUrl { get; set; } = string.Empty;

    [Range(1, int.MaxValue, ErrorMessage = "O limite deve ser um inteiro positivo.")]
    public int Limite { get; set; }

    [ValidateEnumeratedItems]
    public List<Parametro> Parametros { get; set; } = [];

    public sealed class Parametro
    {
        [Required(AllowEmptyStrings = false, ErrorMessage = "O nome do parâmetro é obrigatório.")]
        public string Nome { get; set; } = string.Empty;

        [Required(AllowEmptyStrings = false, ErrorMessage = "O valor do parâmetro é obrigatório.")]
        public string Valor { get; set; } = string.Empty;
    }
}
```

## Registro com validação no boot

```csharp
services
    .AddOptions<WidgetOptions>()
    .Bind(configuration.GetSection(WidgetOptions.SectionName))
    .ValidateDataAnnotations()
    // Validações que DataAnnotations não cobre vão em .Validate(...):
    .Validate(o => o.Parametros.Count > 0, "WidgetOptions: ao menos um parâmetro é obrigatório.")
    .ValidateOnStart();   // <- falha no startup se inválido
```

## Consumo (injeção)

Injete `IOptions<T>` no UseCase ou serviço e leia `.Value`:

```csharp
public sealed class FazAlgoUseCase(IOptions<WidgetOptions> options, /* ... */)
{
    public async Task<Result<FooResponse>> Execute(FooRequest request, CancellationToken ct)
    {
        var baseUrl = options.Value.BaseUrl;
        var parametros = options.Value.Parametros;
        // ...
    }
}
```

> Para config que muda em runtime, use `IOptionsMonitor<T>`; para o caso comum
> (lida no boot e estável), `IOptions<T>` basta.

## `appsettings.json` correspondente

```json
{
  "Widget": {
    "BaseUrl": "https://api.exemplo.interno",
    "Limite": 50,
    "Parametros": [
      { "Nome": "foo", "Valor": "bar" }
    ]
  }
}
```

## Regras

- **Uma classe `Options` por integração/feature configurável**, com `SectionName`.
- **Sempre `ValidateDataAnnotations()` + `ValidateOnStart()`** — sem config
  inválida silenciosa.
- **Regras compostas** (que DataAnnotations não expressa) vão em `.Validate(...)`.
- **Segredos não vão no `appsettings.json` versionado** — use user-secrets em dev
  e o provedor de segredos do ambiente em produção.
