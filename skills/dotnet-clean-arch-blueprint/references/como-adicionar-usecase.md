---
tags: [arquitetura, dotnet, guia, usecase, howto]
aliases: [Como Adicionar UseCase, Novo UseCase]
---

# 📗 Guia: Como adicionar um UseCase

> Passo a passo acionável e auto-contido para criar um novo caso de uso.

Ver também: [camada-application](camada-application.md) · [result-pattern](result-pattern.md) · [validacao-dois-niveis](validacao-dois-niveis.md) · [como-adicionar-endpoint](como-adicionar-endpoint.md)

## Resultado em uma frase

Criar **um arquivo** em `Application/Features/<Recurso>/` contendo Validator +
UseCase + Request + Response, e registrá-lo no `DependencyInjection.cs`.

## Passos

### 1. Crie o arquivo da feature

`src/<Sln>.Application/Features/<Recurso>/<Acao>UseCase.cs`. Os quatro tipos
moram juntos, nesta ordem: **Validator → UseCase → Request → Response**.

### 2. Escreva o Validator (nível de entrada)

FluentValidation, `sealed`. Reaproveite regras de domínio quando existirem
(ex.: `Email.Valido`). Ver [validacao-dois-niveis](validacao-dois-niveis.md).

```csharp
using FluentValidation;

namespace Blueprint.Application.Features.Widgets;

public sealed class AtualizarWidgetValidator : AbstractValidator<AtualizarWidgetRequest>
{
    public AtualizarWidgetValidator()
    {
        RuleFor(x => x.Id).NotEmpty().WithMessage("O Id é obrigatório.");
        RuleFor(x => x.Quantidade)
            .GreaterThanOrEqualTo(0).WithMessage("A quantidade não pode ser negativa.");
    }
}
```

### 3. Escreva o UseCase

Primary constructor para injeção. Único método público `Execute(request, ct)`
retornando [`Result<T>`](result-pattern.md). Fluxo típico: **log → valida →
consulta → aplica regra → persiste → retorna**.

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Blueprint.Application.Abstractions;
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Features.Widgets;

public sealed class AtualizarWidgetUseCase(
    IApplicationDbContext dbContext,
    AtualizarWidgetValidator validator,
    ILogger<AtualizarWidgetUseCase> logger)
{
    public async Task<Result<AtualizarWidgetResponse>> Execute(
        AtualizarWidgetRequest request,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("Atualizando Widget {Id}", request.Id);

        var validation = validator.Validate(request);
        if (!validation.IsValid)
            return Error.Validation([.. validation.Errors.Select(e => e.ErrorMessage)]);

        var widget = await dbContext.Widgets
            .FirstOrDefaultAsync(w => w.Id == request.Id, cancellationToken);

        if (widget is null)
            return Error.NotFound("Widget não encontrado.");

        // Regra de domínio fica na entidade (pode lançar DomainException).
        widget.AlterarQuantidade(request.Quantidade);

        await dbContext.SaveChangesAsync(cancellationToken);

        return new AtualizarWidgetResponse(widget.Id, widget.Quantidade);
    }
}
```

### 4. Declare Request e Response (records)

```csharp
public record AtualizarWidgetRequest(Guid Id, int Quantidade);
public record AtualizarWidgetResponse(Guid Id, int Quantidade);
```

### 5. Registre no DI

Em `Application/DependencyInjection.cs`, adicione o UseCase como **Scoped**. Os
validators já são varridos por `AddValidatorsFromAssembly` — não precisam de
registro individual.

```csharp
services
    .AddScoped<AtualizarWidgetUseCase>();
```

### 6. Exponha via endpoint

Crie o [endpoint correspondente](como-adicionar-endpoint.md) que injeta este UseCase.

## Decisões de modelagem rápidas

- **Consulta sem mutação?** use `.AsNoTracking()`.
- **Recurso não existe?** `Error.NotFound(...)`.
- **Violação de unicidade/estado?** `Error.Conflict(...)`.
- **Input malformado?** Validator → `Error.Validation(...)`.
- **Invariante de domínio?** deixe a entidade lançar `DomainException` (não
  reimplemente a regra no UseCase). Ver [validacao-dois-niveis](validacao-dois-niveis.md).

## Checklist

- [ ] Um arquivo com Validator + UseCase + Request + Response (nessa ordem).
- [ ] `Execute(request, ct)` retorna `Result<T>`.
- [ ] Valida a entrada e devolve `Error.Validation` em caso de falha.
- [ ] Usa `IApplicationDbContext` (nunca o `DbContext` concreto).
- [ ] Registrado como `Scoped` no `DependencyInjection.cs`.
- [ ] Nenhuma exceção usada para fluxo de negócio (ver [result-pattern](result-pattern.md)).
