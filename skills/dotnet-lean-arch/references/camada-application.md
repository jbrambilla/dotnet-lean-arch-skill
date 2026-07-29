---
tags: [arquitetura, dotnet, camada, application, usecase]
aliases: [Application, Camada de Aplicação]
---

# 🟩 Camada Application

> Orquestra os casos de uso. Depende apenas de [Domain](camada-domain.md). Define
> abstrações (`IApplicationDbContext`) que a [Infra](camada-infra.md) implementa.
> **Sem MediatR**.

Ver também: [index](index.md) · [como-adicionar-usecase](como-adicionar-usecase.md) · [result-pattern](result-pattern.md) · [configuracao-tipada](configuracao-tipada.md) · [integracao-servico-externo](integracao-servico-externo.md)

## Padrões e práticas aplicados aqui

- [result-pattern](result-pattern.md) — UseCases retornam `Result<T>`.
- [validacao-dois-niveis](validacao-dois-niveis.md) — o **nível 1** (FluentValidation no UseCase) vive aqui.
- [configuracao-tipada](configuracao-tipada.md) — classes `Options` e seu registro com `ValidateOnStart`.
- [integracao-servico-externo](integracao-servico-externo.md) — a abstração `IXxxGateway` (contrato da integração) é definida aqui.
- [processamento-em-segundo-plano](processamento-em-segundo-plano.md) — UseCases e Jobs (sufixo `Job`) vivem aqui; o enfileiramento usa a abstração `IBackgroundJobService`.

## Padrão UseCase

Cada caso de uso é uma classe simples com um único método público
`Execute(request, ct)` que retorna [`Result<T>`](result-pattern.md). Injetada como
**Scoped** e consumida diretamente pelo endpoint.

### Estrutura do arquivo

Um arquivo por caso de uso, contendo **quatro tipos juntos**, nesta ordem:

1. O `Validator` (FluentValidation) — `sealed`.
2. A classe `UseCase`.
3. O `record Request`.
4. O `record Response`.

```csharp
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Blueprint.Application.Abstractions;
using Blueprint.Domain;
using Blueprint.Domain.Shared;
using Blueprint.Domain.ValueObjects;

namespace Blueprint.Application.Features.Widgets;

// 1. Validator — formato/entrada. Ver [validacao-dois-niveis](validacao-dois-niveis.md).
public sealed class CriarWidgetValidator : AbstractValidator<CriarWidgetRequest>
{
    public CriarWidgetValidator()
    {
        RuleFor(x => x.Nome)
            .NotEmpty().WithMessage("O nome não pode estar vazio.")
            .MaximumLength(120).WithMessage("O nome deve ter no máximo 120 caracteres.");

        RuleFor(x => x.Contato)
            .NotEmpty().WithMessage("O contato não pode estar vazio.")
            .Must(Email.Valido).WithMessage("O e-mail informado é inválido.");

        RuleFor(x => x.Quantidade)
            .GreaterThanOrEqualTo(0).WithMessage("A quantidade não pode ser negativa.");
    }
}

// 2. UseCase — orquestração via primary constructor (injeção).
public sealed class CriarWidgetUseCase(
    IApplicationDbContext dbContext,
    CriarWidgetValidator validator,
    ILogger<CriarWidgetUseCase> logger)
{
    public async Task<Result<CriarWidgetResponse>> Execute(
        CriarWidgetRequest request,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("Criando Widget: {Nome}", request.Nome);

        var validationResult = validator.Validate(request);
        if (!validationResult.IsValid)
            return Error.Validation([.. validationResult.Errors.Select(e => e.ErrorMessage)]);

        var jaExiste = await dbContext.Widgets
            .AsNoTracking()
            .AnyAsync(w => w.Nome == request.Nome, cancellationToken);

        if (jaExiste)
            return Error.Conflict("Já existe um Widget com esse nome.");

        // Invariantes de domínio são garantidas no construtor (DomainException).
        var widget = new Widget(request.Contato, request.Nome, request.Quantidade);

        dbContext.Widgets.Add(widget);
        await dbContext.SaveChangesAsync(cancellationToken);

        logger.LogInformation("Widget criado com Id {Id}", widget.Id);

        return new CriarWidgetResponse(widget.Id, widget.Nome, widget.Quantidade);
    }
}

// 3. Request
public record CriarWidgetRequest(string Nome, string Contato, int Quantidade);

// 4. Response
public record CriarWidgetResponse(Guid Id, string Nome, int Quantidade);
```

> **Leitura de consultas:** use `.AsNoTracking()` quando não houver mutação.

## Abstração `IApplicationDbContext`

A Application **não conhece** o `DbContext` concreto — só esta interface. Isso
mantém a regra de dependência (a Infra implementa, ver [camada-infra](camada-infra.md)).

```csharp
using Microsoft.EntityFrameworkCore;
using Blueprint.Domain;

namespace Blueprint.Application.Abstractions;

public interface IApplicationDbContext
{
    DbSet<Widget> Widgets { get; }
    DbSet<Bar> Bars { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

## Options tipadas

Configuração externa vira classe tipada, validada no boot. Detalhes em
[configuracao-tipada](configuracao-tipada.md).

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Application.Features.Widgets;

public sealed class WidgetOptions
{
    public const string SectionName = "Widget";

    [Required(AllowEmptyStrings = false)]
    public string BaseUrl { get; set; } = string.Empty;

    [Range(1, int.MaxValue)]
    public int LimitePadrao { get; set; }
}
```

## Registro no DI (`DependencyInjection.cs`)

UseCases e options são registrados **manualmente** (sem auto-discovery aqui).
Validators são varridos do assembly.

```csharp
using FluentValidation;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Blueprint.Application.Features.Widgets;

namespace Blueprint.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Options tipadas validadas no boot
        services
            .AddOptions<WidgetOptions>()
            .Bind(configuration.GetSection(WidgetOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();

        // UseCases — Scoped, registro manual
        services
            .AddScoped<CriarWidgetUseCase>();

        // Validators — varredura do assembly (inclui internos)
        services
            .AddValidatorsFromAssembly(
                typeof(DependencyInjection).Assembly,
                includeInternalTypes: true);

        return services;
    }
}
```

## Princípios

- **Um arquivo por caso de uso**, com Validator + UseCase + Request + Response.
- **Sempre retorne `Result<T>`** — nunca lance exceção para fluxo de negócio.
- **Não vaze tipos de Infra** — dependa de `IApplicationDbContext`, nunca do
  `DbContext` concreto.
- **Registre UseCases manualmente** no `DependencyInjection.cs`.
