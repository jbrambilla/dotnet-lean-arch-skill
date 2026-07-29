---
tags: [arquitetura, dotnet, pattern, result, error-handling]
aliases: [Result Pattern, Result, Padrão Result]
---

# 🎯 Result Pattern

> Fluxo de negócio é controlado por valores de retorno (`Result<T>`/`Error`),
> **nunca** por exceções. Exceção é para o **inesperado**, não para o esperado.

Ver também: [index](index.md) · [camada-domain](camada-domain.md) · [camada-api](camada-api.md) · [validacao-dois-niveis](validacao-dois-niveis.md)

## Por quê

- **Explícito:** a assinatura `Task<Result<T>>` diz que a operação pode falhar.
- **Barato:** sem o custo de `throw`/stack unwinding no caminho de falha esperado.
- **Mapeável:** `ErrorType` traduz limpo para status HTTP em um único lugar.

## Os tipos (vivem em `Domain/Shared`)

### `Result` e `Result<T>`

Conversões implícitas deixam o código de retorno enxuto: basta retornar o valor
ou o `Error`.

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

### `Error` e `ErrorType`

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

## Uso no UseCase

Graças às conversões implícitas, retornar sucesso ou erro é direto:

```csharp
public async Task<Result<FooResponse>> Execute(FooRequest request, CancellationToken ct)
{
    var validation = validator.Validate(request);
    if (!validation.IsValid)
        return Error.Validation([.. validation.Errors.Select(e => e.ErrorMessage)]); // -> Result

    var foo = await dbContext.Foos.FirstOrDefaultAsync(f => f.Id == request.Id, ct);
    if (foo is null)
        return Error.NotFound("Foo não encontrado.");   // -> Result

    return new FooResponse(foo.Id, foo.Nome);            // -> Result (sucesso)
}
```

## Mapeamento para HTTP

Um único ponto traduz `ErrorType` → status. Ver implementação em [camada-api](camada-api.md).

| `ErrorType`  | Status HTTP | Observação                                  |
| ------------ | ----------- | ------------------------------------------- |
| `Validation` | **400**     | inclui lista `errors` no ProblemDetails     |
| `NotFound`   | **404**     |                                             |
| `Conflict`   | **409**     |                                             |
| `Failure`    | **500**     | falha genérica de negócio/aplicação         |

No endpoint:

```csharp
var response = await useCase.Execute(request, ct);
if (response.IsFailure)
    return response.Problem();   // ResultExtensions traduz para ProblemDetails
return Results.Ok(response.Value);
```

## Regras

- ✅ **Use `Result`/`Error`** para qualquer falha de negócio esperada (não
  encontrado, conflito, validação, regra violada).
- ❌ **NÃO lance exceção para fluxo de negócio.** Exceções são para o inesperado
  (bug, indisponibilidade de infra) e são capturadas pelo `GlobalExceptionHandler`.
- ⚠️ **`DomainException` é a exceção à regra** — ela protege invariantes de
  domínio na construção de entidades, não orquestra fluxo. Ver
  [validacao-dois-niveis](validacao-dois-niveis.md).
- Chamar `.Problem()` em um `Result` de sucesso é erro de programação (lança).
