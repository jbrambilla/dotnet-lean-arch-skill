---
tags: [architecture, dotnet, pattern, result, error-handling]
aliases: [Result Pattern, Result]
---

# 🎯 Result Pattern

> Business flow is controlled by return values (`Result<T>`/`Error`),
> **never** by exceptions. Exceptions are for the **unexpected**, not the expected.

See also: [index](index.md) · [domain-layer](domain-layer.md) · [api-layer](api-layer.md) · [two-level-validation](two-level-validation.md)

## Why

- **Explicit:** the `Task<Result<T>>` signature says the operation can fail.
- **Cheap:** no `throw`/stack unwinding cost on the expected failure path.
- **Mappable:** `ErrorType` translates cleanly to HTTP status in a single place.

## The types (live in `Domain/Shared`)

### `Result` and `Result<T>`

Implicit conversions keep return code lean: just return the value
or the `Error`.

```csharp
namespace Blueprint.Domain.Shared;

public class Result<T>
{
    public T? Value { get; }
    public Error? Error { get; }
    public bool IsSuccess => Error is null;
    public bool IsFailure => !IsSuccess;

    private Result(T value) => Value = value;
    private Result(Error error) => Error = error;

    public static implicit operator Result<T>(T value) => new(value);
    public static implicit operator Result<T>(Error error) => new(error);
}

public class Result
{
    public Error? Error { get; }
    public bool IsSuccess => Error is null;
    public bool IsFailure => !IsSuccess;

    private Result() { }
    private Result(Error error) => Error = error;

    public static Result Success() => new();
    public static Result Failure(Error error) => new(error);

    public static implicit operator Result(Error error) => new(error);
}
```

### `Error` and `ErrorType`

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

## Usage in the UseCase

Thanks to the implicit conversions, returning success or error is straightforward:

```csharp
public async Task<Result<FooResponse>> Execute(FooRequest request, CancellationToken ct)
{
    var validation = validator.Validate(request);
    if (!validation.IsValid)
        return Error.Validation([.. validation.Errors.Select(e => e.ErrorMessage)]); // -> Result

    var foo = await dbContext.Foos.FirstOrDefaultAsync(f => f.Id == request.Id, ct);
    if (foo is null)
        return Error.NotFound("Foo not found.");   // -> Result

    return new FooResponse(foo.Id, foo.Name);            // -> Result (success)
}
```

## Mapping to HTTP

A single place translates `ErrorType` → status. See the implementation in [api-layer](api-layer.md).

| `ErrorType`  | HTTP status | Note                                        |
| ------------ | ----------- | ------------------------------------------- |
| `Validation` | **400**     | includes the `errors` list in ProblemDetails |
| `NotFound`   | **404**     |                                             |
| `Conflict`   | **409**     |                                             |
| `Failure`    | **500**     | generic business/application failure        |

In the endpoint:

```csharp
var response = await useCase.Execute(request, ct);
if (response.IsFailure)
    return response.Problem();   // ResultExtensions translates to ProblemDetails
return Results.Ok(response.Value);
```

## Rules

- ✅ **Use `Result`/`Error`** for any expected business failure (not
  found, conflict, validation, violated rule).
- ❌ **Do NOT throw exceptions for business flow.** Exceptions are for the unexpected
  (bugs, infra unavailability) and are caught by the `GlobalExceptionHandler`.
- ⚠️ **`DomainException` is the exception to the rule** — it protects domain
  invariants during entity construction; it does not orchestrate flow. See
  [two-level-validation](two-level-validation.md).
- Calling `.Problem()` on a successful `Result` is a programming error (it throws).
