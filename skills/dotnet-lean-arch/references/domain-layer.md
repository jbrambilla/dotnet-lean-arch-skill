---
tags: [architecture, dotnet, layer, domain]
aliases: [Domain, Domain Layer]
---

# 🟦 Domain Layer

> The core. **No external dependencies** (no EF Core, no ASP.NET, no third-party
> packages). Contains entities, value objects, and shared types.

See also: [index](index.md) · [result-pattern](result-pattern.md) · [two-level-validation](two-level-validation.md)

## Patterns and practices applied here

- [result-pattern](result-pattern.md) — the `Result`/`Error`/`ErrorType` types **live in this layer** (`Shared/`).
- [two-level-validation](two-level-validation.md) — **level 2** (invariants via `DomainException`) is the domain's responsibility.

## Shared types (`Shared/`)

### `Entity` base

Every entity inherits from `Entity`. Responsibilities: identity via `Id`
(**GUID v7**, time-sortable) and timestamps. The `CreatedAt`/`UpdatedAt` fields
have `internal` setters — they are populated automatically by the persistence layer,
not by the domain.

```csharp
namespace Blueprint.Domain.Shared;

public abstract class Entity
{
    public Guid Id { get; protected set; }
    public DateTime CreatedAt { get; internal set; }
    public DateTime UpdatedAt { get; internal set; }

    protected Entity(Guid id)
    {
        Id = id;
        CreatedAt = UpdatedAt = DateTime.UtcNow;
    }

    protected Entity() : this(Guid.CreateVersion7()) { }

    public override bool Equals(object? obj)
        => obj is Entity other && Id == other.Id;

    public override int GetHashCode() => HashCode.Combine(Id);
}
```

The `internal` setter only compiles from Infra if that assembly is granted access.
Declare it as an **MSBuild item in the `.csproj`** — **never** create a
`Properties/AssemblyInfo.cs` with `[assembly: InternalsVisibleTo(...)]`
(see [conventions-and-naming](conventions-and-naming.md)):

```xml
<!-- src/<Sln>.Domain/<Sln>.Domain.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <InternalsVisibleTo Include="<Sln>.Infra" />
  </ItemGroup>
</Project>
```

> Who writes the timestamps: `SaveChangesAsync`, in [infra-layer](infra-layer.md).

### `AggregateRoot`

Marks the root of an aggregate (entry point for consistency). It can start
empty and gain behavior (e.g., domain events) as the need arises.

```csharp
namespace Blueprint.Domain.Shared;

public abstract class AggregateRoot : Entity
{
    protected AggregateRoot() { }
    protected AggregateRoot(Guid id) : base(id) { }
}
```

### `DomainException`

Thrown when a **domain invariant** is violated during construction/mutation of
an entity or value object. See [two-level-validation](two-level-validation.md).

```csharp
namespace Blueprint.Domain.Shared;

public sealed class DomainException(string message) : Exception(message);
```

### `Result` / `Error` / `ErrorType`

The heart of the [result-pattern](result-pattern.md). Full documentation in the dedicated note.

```csharp
namespace Blueprint.Domain.Shared;

public enum ErrorType { Failure, NotFound, Conflict, Validation }

public record Error(string Message, ErrorType Type, string[]? ValidationErrors = null)
{
    public static Error Validation(IEnumerable<string> errors) =>
        new("One or more validation errors occurred.", ErrorType.Validation, [.. errors]);
    public static Error NotFound(string message) => new(message, ErrorType.NotFound);
    public static Error Conflict(string message) => new(message, ErrorType.Conflict);
    public static Error Failure(string message) => new(message, ErrorType.Failure);
}
```

## Entities

`internal`/`sealed` entity with private setters and controlled construction.
Private parameterless constructor **only** so EF Core can materialize it. Invariants
are enforced in the public constructor via value objects and `DomainException`.

```csharp
using Blueprint.Domain.Shared;
using Blueprint.Domain.ValueObjects;

namespace Blueprint.Domain;

public sealed class Widget : AggregateRoot
{
    public Email Contact { get; private set; } = null!;
    public string Name { get; private set; } = null!;
    public int Quantity { get; private set; }

    private Widget() { } // EF Core

    public Widget(string contact, string name, int quantity)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new DomainException("The Widget name is required.");
        if (quantity < 0)
            throw new DomainException("The quantity cannot be negative.");

        Contact = Email.Create(contact); // value object validates format
        Name = name;
        Quantity = quantity;
    }

    public void ChangeQuantity(int newQuantity)
    {
        if (newQuantity < 0)
            throw new DomainException("The quantity cannot be negative.");
        Quantity = newQuantity;
    }
}
```

## Value Objects

Immutable, no identity, validated at creation via a static factory. Equality by
**value**. Encapsulates a reusable domain rule (format, normalization).

```csharp
using System.Text.RegularExpressions;
using Blueprint.Domain.Shared;

namespace Blueprint.Domain.ValueObjects;

public sealed class Email
{
    public string Value { get; }

    private Email(string value) => Value = value;

    public static Email Create(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
            throw new DomainException("Email cannot be empty.");

        var normalized = input.Trim().ToLowerInvariant();

        if (!IsValid(normalized))
            throw new DomainException("Invalid email.");

        return new Email(normalized);
    }

    // Reusable domain rule — also consumed by input validators.
    public static bool IsValid(string value)
        => !string.IsNullOrWhiteSpace(value)
           && Regex.IsMatch(value, @"^[^@\s]+@[^@\s]+\.[^@\s]+$");

    public override bool Equals(object? obj)
        => obj is Email other && Value == other.Value;

    public override int GetHashCode() => Value.GetHashCode();
    public override string ToString() => Value;

    public static implicit operator string(Email email) => email.Value;
}
```

> The static `IsValid(...)` function is **reused** by the input Validator in the
> [application-layer](application-layer.md) — see [two-level-validation](two-level-validation.md). This avoids duplicating the
> rule between format (input) and invariant (domain).

## Principles

- **Purity:** if you needed a `using` for EF Core or ASP.NET, you are in the wrong
  place. Move it to [infra-layer](infra-layer.md) or [application-layer](application-layer.md).
- **Always-valid construction:** an entity never exists in an invalid state —
  guarantee it in the constructor.
- **No flow logic:** the domain throws `DomainException` for invariants;
  application flow decisions use [Result](result-pattern.md) in the Application.
