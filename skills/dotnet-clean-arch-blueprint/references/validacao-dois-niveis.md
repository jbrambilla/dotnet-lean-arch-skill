---
tags: [arquitetura, dotnet, pattern, validacao, fluentvalidation]
aliases: [Validação em Dois Níveis, Validação]
---

# ✅ Validação em Dois Níveis

> Duas linhas de defesa com responsabilidades distintas: **formato/entrada**
> (FluentValidation, na Application) e **invariantes de domínio**
> (`DomainException`, no Domain).

Ver também: [index](index.md) · [camada-application](camada-application.md) · [camada-domain](camada-domain.md) · [result-pattern](result-pattern.md)

## A distinção

| Nível | Onde | Mecanismo | Responde por | Em caso de falha |
| ----- | ---- | --------- | ------------ | ---------------- |
| **1. Entrada/formato** | [camada-application](camada-application.md) | FluentValidation no UseCase | "O input está bem-formado?" | `Error.Validation` → **400** |
| **2. Invariante de domínio** | [camada-domain](camada-domain.md) | `DomainException` no construtor | "O objeto pode existir nesse estado?" | exceção (rede de segurança) |

A ideia: a maioria dos inputs ruins é barrada cedo e devolve **400 amigável**.
O domínio ainda se protege de estados inválidos como **última linha** — mas, no
fluxo feliz, o nível 1 já garantiu a entrada, então o nível 2 raramente dispara.

## Nível 1 — FluentValidation (formato/entrada)

Valida a `Request` antes de tocar o domínio. Mensagens claras, agregadas e
devolvidas como [`Error.Validation`](result-pattern.md).

```csharp
public sealed class CriarBarValidator : AbstractValidator<CriarBarRequest>
{
    public CriarBarValidator()
    {
        RuleFor(x => x.Codigo)
            .NotEmpty().WithMessage("O código não pode estar vazio.")
            .Length(8).WithMessage("O código deve ter exatamente 8 caracteres.")
            .Matches(@"^\d+$").WithMessage("O código deve conter apenas números.")
            .Must(Codigo.Valido).WithMessage("O código informado é inválido.");
    }
}
```

No UseCase:

```csharp
var validationResult = validator.Validate(request);
if (!validationResult.IsValid)
    return Error.Validation([.. validationResult.Errors.Select(e => e.ErrorMessage)]);
```

## Nível 2 — DomainException (invariantes)

O construtor da entidade/value object recusa estados inválidos. Garante que um
objeto **nunca existe inválido**, independentemente de quem o cria.

```csharp
public sealed class Bar : AggregateRoot
{
    public Codigo Codigo { get; private set; } = null!;

    private Bar() { }

    public Bar(string codigo)
    {
        // Última linha de defesa: protege a invariante mesmo se o nível 1 falhar.
        Codigo = Codigo.Criar(codigo); // lança DomainException se inválido
    }
}
```

## Regra compartilhada, sem duplicação

A regra "núcleo" (ex.: validação de um formato/checksum) mora **uma vez** no
value object como método estático e é **reutilizada** pelo validator de entrada.
Evita duas implementações divergentes da mesma regra.

```csharp
// Domain/ValueObjects/Codigo.cs
public sealed class Codigo
{
    public string Valor { get; }
    private Codigo(string valor) => Valor = valor;

    public static Codigo Criar(string entrada)
    {
        if (!Valido(entrada))
            throw new DomainException("Código inválido.");
        return new Codigo(entrada);
    }

    // Regra única — reaproveitada pelo Validator (nível 1).
    public static bool Valido(string codigo) => /* checksum/lógica do formato */ true;
}
```

```csharp
// Application — o Validator referencia a MESMA regra:
RuleFor(x => x.Codigo).Must(Codigo.Valido).WithMessage("O código informado é inválido.");
```

## Regras

- **Nível 1 (FluentValidation)** trata o caminho esperado de input inválido →
  `Error.Validation` → 400. É o que o usuário normalmente vê.
- **Nível 2 (DomainException)** é a salvaguarda da consistência do domínio; não é
  para controle de fluxo. Não a use no lugar do [Result](result-pattern.md).
- **A regra de formato mora no Domain** (value object) e é **reutilizada** pelo
  validator — nunca duplicada.
