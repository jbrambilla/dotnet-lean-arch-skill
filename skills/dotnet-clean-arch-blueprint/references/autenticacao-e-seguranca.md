---
tags: [arquitetura, dotnet, pattern, seguranca, autenticacao, api-key]
aliases: [Autenticação e Segurança, Auth, API Key, Segurança]
---

# 🔐 Autenticação e Segurança

> A autenticação vive na [Api](camada-api.md), usando o esquema **nativo** de
> autenticação/autorização do ASP.NET. A proteção é **explícita por endpoint**
> (`.RequireAuthorization()` nos protegidos, `.AllowAnonymous()` nos públicos) — a
> intenção fica visível no próprio mapeamento. O mecanismo padrão deste blueprint é
> **API Key** (validada em memória, ideal para APIs internas), mas a escolha depende
> do cenário — ver o panorama abaixo.

Ver também: [index](index.md) · [camada-api](camada-api.md) · [configuracao-tipada](configuracao-tipada.md) · [result-pattern](result-pattern.md) · API

## Escolha do mecanismo

| Mecanismo | Quando usar | A app… | Custo |
| --------- | ----------- | ------ | ----- |
| **API Key** | API **interna**/fechada, server-to-server, rede privada | …valida a chave em memória | mínimo (sem infra) |
| **JWT + Auth Server** (Keycloak, Auth0, Entra ID) | API **pública**, múltiplos clientes, frontend (OIDC/PKCE), SSO | …só **valida o token** (issuer, audience, chave pública) | médio (servidor externo) |
| **EF Core Identity** | App com **login próprio**, sem auth server, controle total de usuários/roles | …gerencia usuários, senhas, roles no próprio banco | médio/alto (gestão local) |

> **Regra prática:** comece pelo mais simples que atende o cenário. Para API
> interna, **API Key** basta. Se um dia abrir para frontend/terceiros, migre para
> **JWT** (a estrutura abaixo facilita — só troca o esquema de autenticação).

---

## API Key (mecanismo padrão)

Implementado como um **esquema de autenticação nativo** (`AuthenticationHandler`),
não como middleware avulso. Assim `[Authorize]`/`[AllowAnonymous]`, claims e
`HttpContext.User` funcionam de forma idiomática, e a migração para JWT é só trocar
o esquema.

### 1. Options (validadas no boot)

A chave nunca é hardcoded: vem de `appsettings` → variável de ambiente
(App Service) → **Key Vault** em produção. Ver [configuracao-tipada](configuracao-tipada.md).

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Api.Security;

internal sealed class SecurityOptions
{
    public const string SectionName = "Security";

    [ValidateEnumeratedItems]   // valida os DataAnnotations de cada item da lista
    public List<ApiKeySettings> ApiKeys { get; set; } = [];
}

internal sealed class ApiKeySettings
{
    [Required(AllowEmptyStrings = false, ErrorMessage = "Security ApiKey: o nome (client) é obrigatório.")]
    public string Name { get; set; } = string.Empty;

    [Required(AllowEmptyStrings = false, ErrorMessage = "Security ApiKey: a chave é obrigatória.")]
    public string Key { get; set; } = string.Empty;
}
```

> `[ValidateEnumeratedItems]` aplica a validação **a cada item** da lista (não só à
> lista). Combinado com o `.Validate(... Count > 0 ...)` no registro (abaixo),
> garante que há **ao menos uma** chave **e** que cada uma está completa.

```json
// appsettings.json (chaves reais só via env var / Key Vault)
{
  "Security": {
    "ApiKeys": [
      { "Name": "App-A", "Key": "<uuid-via-secret>" },
      { "Name": "App-B", "Key": "<uuid-via-secret>" }
    ]
  }
}
```

### 2. AuthenticationHandler

Valida o header `X-Api-Key`, compara em **tempo constante** e emite um principal
com o `Name` da credencial como claim. Recusa escrevendo **`ProblemDetails`**
direto (sem lançar exceção) — coerente com o formato de erro do API.

```csharp
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Blueprint.Api.Security;

internal sealed class ApiKeyAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    IOptions<SecurityOptions> security)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "ApiKey";
    private const string HeaderName = "X-Api-Key";

    private readonly SecurityOptions _security = security.Value;

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        // Sem header: não é "falha", é "ausência" — deixa o challenge (401) decidir.
        if (!Request.Headers.TryGetValue(HeaderName, out var provided) ||
            string.IsNullOrWhiteSpace(provided))
            return Task.FromResult(AuthenticateResult.NoResult());

        var match = _security.ApiKeys.FirstOrDefault(k => FixedTimeEquals(k.Key, provided!));
        if (match is null)
            return Task.FromResult(AuthenticateResult.Fail("API Key inválida."));

        Claim[] claims = [new(ClaimTypes.Name, match.Name), new("client_id", match.Name)];
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme.Name));
        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(principal, Scheme.Name)));
    }

    // 401 — não autenticado (ausente ou inválida).
    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
        => WriteProblem(StatusCodes.Status401Unauthorized,
            "Credencial ausente ou inválida.");

    // 403 — autenticado, mas sem permissão para o recurso.
    protected override Task HandleForbiddenAsync(AuthenticationProperties properties)
        => WriteProblem(StatusCodes.Status403Forbidden,
            "Acesso negado para esta credencial.");

    private async Task WriteProblem(int status, string detail)
    {
        Response.StatusCode = status;
        Response.ContentType = "application/problem+json";
        await Response.WriteAsync(JsonSerializer.Serialize(new
        {
            title = status == 401 ? "Não autorizado" : "Acesso negado",
            status,
            detail
        }));
    }

    // Comparação em tempo constante evita timing attack (lengths diferentes → false).
    private static bool FixedTimeEquals(string a, string b)
        => CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));
}
```

### 3. Registro no DI

Sem `FallbackPolicy` — a autorização é declarada **explicitamente em cada endpoint**
(ver passo 5). O `AddAuthorization()` fica simples.

```csharp
using Microsoft.AspNetCore.Authentication;

namespace Blueprint.Api.Security;

internal static class SecurityExtensions
{
    public static IServiceCollection AddApiKeyAuth(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<SecurityOptions>()
            .Bind(configuration.GetSection(SecurityOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(o => o.ApiKeys.Count > 0, "Security: ao menos uma API Key.")
            .ValidateOnStart();

        services.AddAuthentication(ApiKeyAuthenticationHandler.SchemeName)
            .AddScheme<AuthenticationSchemeOptions, ApiKeyAuthenticationHandler>(
                ApiKeyAuthenticationHandler.SchemeName, _ => { });

        services.AddAuthorization();   // proteção é explícita por endpoint

        return services;
    }
}
```

### 4. Pipeline (`Program.cs`)

```csharp
builder.Services.AddApiKeyAuth(builder.Configuration);
// ...
app.UseAuthentication();
app.UseAuthorization();   // antes de MapEndpoints
```

### 5. Autorização explícita por endpoint

Cada endpoint declara sua intenção — protegido com `.RequireAuthorization()`,
público com `.AllowAnonymous()`. A semântica fica visível no mapeamento. Ver
[como-adicionar-endpoint](como-adicionar-endpoint.md).

```csharp
// Protegido: exige X-Api-Key
app.MapGet("api/v1/widgets/{id:guid}", handler)
   .RequireAuthorization();

// Público
app.MapGet("/", () => Results.Ok(/* health/info */))
   .AllowAnonymous();
```

> ⚠️ **Trade-off da escolha explícita:** sem `FallbackPolicy`, um endpoint **sem**
> `.RequireAuthorization()` fica **aberto**. Ganhamos clareza semântica, mas a
> responsabilidade é do autor — considere um **teste de integração** que garanta
> 401 nas rotas sensíveis sem credencial. (Health checks e OpenAPI ficam públicos
> por padrão, o que costuma ser o desejado.)

### Acessando o chamador (`IUserContext`)

O handler emite o `client_id` como **claim** no `HttpContext.User`. Para que os
UseCases acessem o chamador **sem conhecer `HttpContext`**, exponha uma abstração
`IUserContext` na [Application](camada-application.md), implementada na
[Infra](camada-infra.md) lendo a claim.

```csharp
// Application/Abstractions/Authentication/IUserContext.cs
namespace Blueprint.Application.Abstractions.Authentication;

public interface IUserContext
{
    string ClientId { get; }
}
```

```csharp
// Infra/Authentication/UserContext.cs
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Blueprint.Application.Abstractions.Authentication;

namespace Blueprint.Infra.Authentication;

internal sealed class UserContext(IHttpContextAccessor accessor) : IUserContext
{
    // Lê do ClaimsPrincipal populado pelo handler — NÃO de HttpContext.Items.
    public string ClientId =>
        accessor.HttpContext?.User.FindFirstValue("client_id")
        ?? throw new UnauthorizedAccessException("Operação requer um ClientId autenticado.");
}
```

Registro (no DI da Infra):

```csharp
services.AddHttpContextAccessor();              // necessário para ler o HttpContext
services.AddScoped<IUserContext, UserContext>();
```

Uso em um UseCase:

```csharp
public sealed class CriarWidgetUseCase(IUserContext userContext, /* ... */)
{
    public async Task<Result<...>> Execute(...)
    {
        var clientId = userContext.ClientId;   // quem chamou (auditoria, escopo, ...)
        // ...
    }
}
```

> O `throw` no getter é **defensivo**: em endpoint com `.RequireAuthorization()`, o
> `client_id` sempre estará presente. Ele protege contra uso indevido em um contexto
> não autenticado. O mesmo `client_id` enriquece os logs do Serilog (ver
> [logging-observabilidade](logging-observabilidade.md)).

---

## Segredos

- **Nunca** versione chaves reais. `appsettings.json` carrega só placeholders.
- Dev: **user-secrets**. Produção: **variáveis de ambiente** (App Service) ou,
  preferencialmente, **Key Vault** (com referência nas app settings).
- Rotação: por ser uma **lista** de chaves, dá para rotacionar sem downtime
  (adiciona a nova, migra os clientes, remove a antiga).

## HTTPS

Mantenha `app.UseHttpsRedirection()`. Para API interna atrás de gateway/Front Door
com TLS terminado, ajuste conforme a topologia, mas **não** trafegue a chave em
canal não cifrado.

## Migração para JWT (quando abrir para frontend/terceiros)

A estrutura não muda: troca-se o **esquema** de autenticação por
`AddAuthentication().AddJwtBearer(...)` configurando `Authority`/`Audience` e a
validação de assinatura (a app **valida** o token, não o emite). O resto
(autorização explícita por endpoint, `[AllowAnonymous]`, claims, `ProblemDetails`)
permanece.

## Princípios

- **Autorização explícita por endpoint** (`.RequireAuthorization()` / `.AllowAnonymous()`)
  — a intenção fica visível no mapeamento; cubra rotas sensíveis com teste.
- **Esquema de autenticação nativo**, não middleware avulso — integra com
  `[Authorize]`, claims e `HttpContext.User`.
- **Recusa com `ProblemDetails`** (401/403), não com exceção.
- **API Key ausente _ou_ inválida → 401**; **403** só para autorização negada.
- **Acesso ao chamador via `IUserContext`** (lê a claim `client_id`), não `HttpContext.Items`.
- **Comparação em tempo constante** e validação no boot (`[ValidateEnumeratedItems]`
  + `ValidateOnStart`).
- **Segredos fora do versionamento**.
- **Confirme a API atual** de autenticação/autorização via Context7 / Microsoft Learn.
