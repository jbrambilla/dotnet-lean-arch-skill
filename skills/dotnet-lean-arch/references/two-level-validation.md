---
tags: [architecture, dotnet, pattern, validation, fluentvalidation]
aliases: [Two-Level Validation, Validation]
---

# ✅ Two-Level Validation

> Two lines of defense with distinct responsibilities: **format/input**
> (FluentValidation, in Application) and **domain invariants**
> (`DomainException`, in Domain).

See also: [index](index.md) · [application-layer](application-layer.md) · [domain-layer](domain-layer.md) · [result-pattern](result-pattern.md)

## The distinction

| Level | Where | Mechanism | Answers for | On failure |
| ----- | ---- | --------- | ------------ | ---------------- |
| **1. Input/format** | [application-layer](application-layer.md) | FluentValidation in the UseCase | "Is the input well-formed?" | `Error.Validation` → **400** |
| **2. Domain invariant** | [domain-layer](domain-layer.md) | `DomainException` in the constructor | "Can the object exist in this state?" | exception (safety net) |

The idea: most bad inputs are blocked early and return a **friendly 400**.
The domain still protects itself from invalid states as the **last line** — but, on
the happy path, level 1 has already guaranteed the input, so level 2 rarely fires.

## Level 1 — FluentValidation (format/input)

Validates the `Request` before touching the domain. Clear messages, aggregated and
returned as [`Error.Validation`](result-pattern.md).

```csharp
public sealed class CreateBarValidator : AbstractValidator<CreateBarRequest>
{
    public CreateBarValidator()
    {
        RuleFor(x => x.Code)
            .NotEmpty().WithMessage("The code must not be empty.")
            .Length(8).WithMessage("The code must be exactly 8 characters long.")
            .Matches(@"^\d+$").WithMessage("The code must contain only digits.")
            .Must(Code.IsValid).WithMessage("The provided code is invalid.");
    }
}
```

In the UseCase:

```csharp
var validationResult = validator.Validate(request);
if (!validationResult.IsValid)
    return Error.Validation([.. validationResult.Errors.Select(e => e.ErrorMessage)]);
```

## Level 2 — DomainException (invariants)

The entity/value object constructor rejects invalid states. It guarantees that an
object **never exists in an invalid state**, regardless of who creates it.

```csharp
public sealed class Bar : AggregateRoot
{
    public Code Code { get; private set; } = null!;

    private Bar() { }

    public Bar(string code)
    {
        // Last line of defense: protects the invariant even if level 1 fails.
        Code = Code.Create(code); // throws DomainException if invalid
    }
}
```

## Shared rule, no duplication

The "core" rule (e.g., a format/checksum validation) lives **once** in the
value object as a static method and is **reused** by the input validator.
This avoids two divergent implementations of the same rule.

```csharp
// Domain/ValueObjects/Code.cs
public sealed class Code
{
    public string Value { get; }
    private Code(string value) => Value = value;

    public static Code Create(string input)
    {
        if (!IsValid(input))
            throw new DomainException("Invalid code.");
        return new Code(input);
    }

    // Single rule — reused by the Validator (level 1).
    public static bool IsValid(string code) => /* checksum/format logic */ true;
}
```

```csharp
// Application — the Validator references the SAME rule:
RuleFor(x => x.Code).Must(Code.IsValid).WithMessage("The provided code is invalid.");
```

## Rules

- **Level 1 (FluentValidation)** handles the expected path of invalid input →
  `Error.Validation` → 400. It is what the user normally sees.
- **Level 2 (DomainException)** is the safeguard of domain consistency; it is not
  for flow control. Do not use it in place of [Result](result-pattern.md).
- **The format rule lives in the Domain** (value object) and is **reused** by the
  validator — never duplicated.
