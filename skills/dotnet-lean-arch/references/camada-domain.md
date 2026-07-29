---
tags: [arquitetura, dotnet, camada, domain]
aliases: [Domain, Camada de Domínio]
---

# 🟦 Camada Domain

> O núcleo. **Sem dependências externas** (nem EF Core, nem ASP.NET, nem pacotes
> de terceiros). Contém entidades, value objects e tipos compartilhados.

Ver também: [index](index.md) · [result-pattern](result-pattern.md) · [validacao-dois-niveis](validacao-dois-niveis.md)

## Padrões e práticas aplicados aqui

- [result-pattern](result-pattern.md) — os tipos `Result`/`Error`/`ErrorType` **moram nesta camada** (`Shared/`).
- [validacao-dois-niveis](validacao-dois-niveis.md) — o **nível 2** (invariantes via `DomainException`) é responsabilidade do domínio.

## Tipos compartilhados (`Shared/`)

### `Entity` base

Toda entidade herda de `Entity`. Responsabilidades: identidade por `Id`
(**GUID v7**, ordenável por tempo) e timestamps. Os campos `CriadoAs`/`AtualizadoAs`
têm setter `internal` — são preenchidos automaticamente na camada de persistência,
não pelo domínio.

```csharp
namespace Blueprint.Domain.Shared;

public abstract class Entity
{
    public Guid Id { get; protected set; }
    public DateTime CriadoAs { get; internal set; }
    public DateTime AtualizadoAs { get; internal set; }

    protected Entity(Guid id)
    {
        Id = id;
        CriadoAs = AtualizadoAs = DateTime.UtcNow;
    }

    protected Entity() : this(Guid.CreateVersion7()) { }

    public override bool Equals(object? obj)
        => obj is Entity other && Id == other.Id;

    public override int GetHashCode() => HashCode.Combine(Id);
}
```

### `AggregateRoot`

Marca a raiz de um agregado (ponto de entrada para consistência). Pode começar
vazia e ganhar comportamento (ex.: domain events) conforme a necessidade.

```csharp
namespace Blueprint.Domain.Shared;

public abstract class AggregateRoot : Entity
{
    protected AggregateRoot() { }
    protected AggregateRoot(Guid id) : base(id) { }
}
```

### `DomainException`

Lançada quando uma **invariante de domínio** é violada na construção/mutação de
uma entidade ou value object. Ver [validacao-dois-niveis](validacao-dois-niveis.md).

```csharp
namespace Blueprint.Domain.Shared;

public sealed class DomainException(string mensagem) : Exception(mensagem);
```

### `Result` / `Error` / `ErrorType`

O coração do [result-pattern](result-pattern.md). Documentação completa na nota dedicada.

```csharp
namespace Blueprint.Domain.Shared;

public enum ErrorType { Failure, NotFound, Conflict, Validation }

public record Error(string Mensagem, ErrorType Type, string[]? ValidationErrors = null)
{
    public static Error Validation(IEnumerable<string> errors) =>
        new("Um ou mais erros de validação ocorreram.", ErrorType.Validation, [.. errors]);
    public static Error NotFound(string mensagem) => new(mensagem, ErrorType.NotFound);
    public static Error Conflict(string mensagem) => new(mensagem, ErrorType.Conflict);
    public static Error Failure(string mensagem) => new(mensagem, ErrorType.Failure);
}
```

## Entidades

Entidade `internal`/`sealed` com setters privados e construção controlada.
Construtor privado sem args **apenas** para o EF Core materializar. As invariantes
são garantidas no construtor público via value objects e `DomainException`.

```csharp
using Blueprint.Domain.Shared;
using Blueprint.Domain.ValueObjects;

namespace Blueprint.Domain;

public sealed class Widget : AggregateRoot
{
    public Email Contato { get; private set; } = null!;
    public string Nome { get; private set; } = null!;
    public int Quantidade { get; private set; }

    private Widget() { } // EF Core

    public Widget(string contato, string nome, int quantidade)
    {
        if (string.IsNullOrWhiteSpace(nome))
            throw new DomainException("O nome do Widget é obrigatório.");
        if (quantidade < 0)
            throw new DomainException("A quantidade não pode ser negativa.");

        Contato = Email.Criar(contato); // value object valida formato
        Nome = nome;
        Quantidade = quantidade;
    }

    public void AlterarQuantidade(int novaQuantidade)
    {
        if (novaQuantidade < 0)
            throw new DomainException("A quantidade não pode ser negativa.");
        Quantidade = novaQuantidade;
    }
}
```

## Value Objects

Imutável, sem identidade, validado na criação por factory estática. Igualdade por
**valor**. Encapsula uma regra de domínio (formato, normalização) reutilizável.

```csharp
using System.Text.RegularExpressions;
using Blueprint.Domain.Shared;

namespace Blueprint.Domain.ValueObjects;

public sealed class Email
{
    public string Valor { get; }

    private Email(string valor) => Valor = valor;

    public static Email Criar(string entrada)
    {
        if (string.IsNullOrWhiteSpace(entrada))
            throw new DomainException("E-mail não pode ser vazio.");

        var normalizado = entrada.Trim().ToLowerInvariant();

        if (!Valido(normalizado))
            throw new DomainException("E-mail inválido.");

        return new Email(normalizado);
    }

    // Regra de domínio reutilizável — também consumida por validators de entrada.
    public static bool Valido(string valor)
        => !string.IsNullOrWhiteSpace(valor)
           && Regex.IsMatch(valor, @"^[^@\s]+@[^@\s]+\.[^@\s]+$");

    public override bool Equals(object? obj)
        => obj is Email other && Valor == other.Valor;

    public override int GetHashCode() => Valor.GetHashCode();
    public override string ToString() => Valor;

    public static implicit operator string(Email email) => email.Valor;
}
```

> A função estática `Valido(...)` é **reutilizada** pelo Validator de entrada na
> [camada-application](camada-application.md) — ver [validacao-dois-niveis](validacao-dois-niveis.md). Isso evita duplicar a
> regra entre formato (entrada) e invariante (domínio).

## Princípios

- **Pureza:** se você precisou de um `using` de EF Core ou ASP.NET, está no lugar
  errado. Mova para [camada-infra](camada-infra.md) ou [camada-application](camada-application.md).
- **Construção sempre válida:** uma entidade nunca existe em estado inválido —
  garanta no construtor.
- **Sem lógica de fluxo:** o domínio lança `DomainException` para invariantes;
  decisões de fluxo de aplicação usam [Result](result-pattern.md) na Application.
