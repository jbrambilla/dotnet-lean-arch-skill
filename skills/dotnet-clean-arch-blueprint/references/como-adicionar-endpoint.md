---
tags: [arquitetura, dotnet, guia, endpoint, howto]
aliases: [Como Adicionar Endpoint, Novo Endpoint]
---

# 📘 Guia: Como adicionar um Endpoint

> Passo a passo acionável e auto-contido para expor uma nova rota HTTP.
> Pré-requisitos: já existe (ou será criado) o [UseCase](como-adicionar-usecase.md)
> correspondente.

Ver também: [camada-api](camada-api.md) · [result-pattern](result-pattern.md) · [como-adicionar-usecase](como-adicionar-usecase.md) · [autenticacao-e-seguranca](autenticacao-e-seguranca.md)

## Resultado em uma frase

Criar uma classe `internal sealed : IEndpoint` na pasta `Endpoints/`. O
auto-registro cuida do resto — **você não toca no `Program.cs`**.

## Passos

### 1. Crie o arquivo do endpoint

Em `src/<Sln>.Api/Endpoints/<Recurso>/<Acao>.cs`. Convenção de pasta por recurso.

### 2. Implemente `IEndpoint`

Classe `internal sealed`. Mapeie a rota no `MapEndpoint`, injetando o UseCase e o
`CancellationToken` como parâmetros do handler (resolvidos pelo DI).

```csharp
using Blueprint.Api.Extensions;
using Blueprint.Application.Features.Widgets;

namespace Blueprint.Api.Endpoints.Widgets;

internal sealed class ObterWidgetPorId : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app)
    {
        app.MapGet("api/v1/widgets/{id:guid}",
            async (Guid id,
                   ObterWidgetPorIdUseCase useCase,
                   CancellationToken cancellationToken) =>
        {
            var request = new ObterWidgetPorIdRequest(id);
            var response = await useCase.Execute(request, cancellationToken);

            if (response.IsFailure)
                return response.Problem();      // 404/400/409/500 conforme ErrorType

            return Results.Ok(response.Value);
        })
        .Produces<ObterWidgetPorIdResponse>(StatusCodes.Status200OK)
        .WithTags(Tags.Widgets)
        .RequireAuthorization();   // protegido (ver passo 5)
    }
}
```

### 3. Traduza o resultado

- **Sucesso:** `Results.Ok(response.Value)` (ou `Created`, `NoContent`, etc.).
- **Falha:** `return response.Problem();` — o [result-pattern](result-pattern.md) mapeia o
  `ErrorType` para o status HTTP correto via `ResultExtensions`.

### 4. Documente para o OpenAPI

- `.Produces<TResponse>(StatusCodes.Status200OK)` no contrato de sucesso.
- `.WithTags(Tags.<Recurso>)` para agrupar (adicione a constante em `Tags` se nova).

### 5. Declare a autorização (sempre explícita)

Não há `FallbackPolicy` — **todo endpoint declara sua intenção**, por semântica e
clareza. Escolha uma:

- **Protegido** (exige credencial, ex.: `X-Api-Key`):
  ```csharp
  .RequireAuthorization();
  ```
- **Público** (sem credencial — ex.: health, info, webhooks):
  ```csharp
  .AllowAnonymous();
  ```

> ⚠️ Esquecer de declarar deixa o endpoint **aberto**. Marque sempre — e, para
> rotas sensíveis, garanta com teste que respondem **401** sem credencial. Detalhes
> do mecanismo em [autenticacao-e-seguranca](autenticacao-e-seguranca.md).

### 6. Pronto — sem registro manual

Ao subir a app, `AddEndpoints(assembly)` descobre a classe e `MapEndpoints()` a
mapeia (ver [camada-api](camada-api.md)). Nenhuma alteração em `Program.cs`.

## Checklist

- [ ] Arquivo em `Endpoints/<Recurso>/`, classe `internal sealed : IEndpoint`.
- [ ] Handler injeta o UseCase + `CancellationToken`.
- [ ] Chama `useCase.Execute(...)` e checa `IsFailure` → `.Problem()`.
- [ ] `.Produces<T>(...)` e `.WithTags(...)` configurados.
- [ ] **Autorização declarada explicitamente**: `.RequireAuthorization()` ou `.AllowAnonymous()`.
- [ ] **Nenhuma** lógica de negócio no endpoint (ela vive no UseCase).
- [ ] Não precisou editar `Program.cs`.

## Anti-padrões a evitar

- ❌ Lógica de negócio/consulta a banco direto no handler → mova para o UseCase.
- ❌ `try/catch` para regras de negócio → use [Result](result-pattern.md).
- ❌ Registrar a rota manualmente em `Program.cs` → o auto-registro já faz.
