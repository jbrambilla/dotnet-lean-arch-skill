---
tags: [architecture, dotnet, pattern, security, authentication, api-key]
aliases: [Authentication and Security, Auth, API Key, Security]
---

# 🔐 Authentication and Security

> Authentication lives in the [Api](api-layer.md) layer, using ASP.NET's **native**
> authentication/authorization scheme. Protection is **explicit per endpoint**
> (`.RequireAuthorization()` on protected ones, `.AllowAnonymous()` on public ones) — the
> intent is visible in the mapping itself. This blueprint's default mechanism is
> **API Key** (validated in memory, ideal for internal APIs), but the choice depends
> on the scenario — see the overview below.

See also: [index](index.md) · [api-layer](api-layer.md) · [typed-configuration](typed-configuration.md) · [result-pattern](result-pattern.md) · API

## Choosing the mechanism

| Mechanism | When to use | The app… | Cost |
| --------- | ----------- | ------ | ----- |
| **API Key** | **Internal**/closed API, server-to-server, private network | …validates the key in memory | minimal (no infra) |
| **JWT + Auth Server** (Keycloak, Auth0, Entra ID) | **Public** API, multiple clients, frontend (OIDC/PKCE), SSO | …only **validates the token** (issuer, audience, public key) | medium (external server) |
| **EF Core Identity** | App with **its own login**, no auth server, full control of users/roles | …manages users, passwords, roles in its own database | medium/high (local management) |

> **Rule of thumb:** start with the simplest option that fits the scenario. For an
> internal API, **API Key** is enough. If someday you open up to frontend/third
> parties, migrate to **JWT** (the structure below makes it easy — just swap the
> authentication scheme).

---

## API Key (default mechanism)

Implemented as a **native authentication scheme** (`AuthenticationHandler`),
not as a standalone middleware. This way `[Authorize]`/`[AllowAnonymous]`, claims and
`HttpContext.User` work idiomatically, and migrating to JWT is just a matter of
swapping the scheme.

### 1. Options (validated at boot)

The key is never hardcoded: it comes from `appsettings` → environment variable
(App Service) → **Key Vault** in production. See [typed-configuration](typed-configuration.md).

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Api.Security;

internal sealed class SecurityOptions
{
    public const string SectionName = "Security";

    [ValidateEnumeratedItems]   // validates the DataAnnotations of each item in the list
    public List<ApiKeySettings> ApiKeys { get; set; } = [];
}

internal sealed class ApiKeySettings
{
    [Required(AllowEmptyStrings = false, ErrorMessage = "Security ApiKey: the name (client) is required.")]
    public string Name { get; set; } = string.Empty;

    [Required(AllowEmptyStrings = false, ErrorMessage = "Security ApiKey: the key is required.")]
    public string Key { get; set; } = string.Empty;
}
```

> `[ValidateEnumeratedItems]` applies validation **to each item** in the list (not just
> the list itself). Combined with the `.Validate(... Count > 0 ...)` in the registration
> (below), it guarantees there is **at least one** key **and** that each one is complete.

```json
// appsettings.json (real keys only via env var / Key Vault)
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

Validates the `X-Api-Key` header, compares in **constant time** and issues a principal
with the credential's `Name` as a claim. Rejects by writing **`ProblemDetails`**
directly (without throwing an exception) — consistent with the API's error format.

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
        // No header: it's not "failure", it's "absence" — let the challenge (401) decide.
        if (!Request.Headers.TryGetValue(HeaderName, out var provided) ||
            string.IsNullOrWhiteSpace(provided))
            return Task.FromResult(AuthenticateResult.NoResult());

        var match = _security.ApiKeys.FirstOrDefault(k => FixedTimeEquals(k.Key, provided!));
        if (match is null)
            return Task.FromResult(AuthenticateResult.Fail("Invalid API Key."));

        Claim[] claims = [new(ClaimTypes.Name, match.Name), new("client_id", match.Name)];
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme.Name));
        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(principal, Scheme.Name)));
    }

    // 401 — not authenticated (missing or invalid).
    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
        => WriteProblem(StatusCodes.Status401Unauthorized,
            "Missing or invalid credential.");

    // 403 — authenticated, but not allowed to access the resource.
    protected override Task HandleForbiddenAsync(AuthenticationProperties properties)
        => WriteProblem(StatusCodes.Status403Forbidden,
            "Access denied for this credential.");

    private async Task WriteProblem(int status, string detail)
    {
        Response.StatusCode = status;
        Response.ContentType = "application/problem+json";
        await Response.WriteAsync(JsonSerializer.Serialize(new
        {
            title = status == 401 ? "Unauthorized" : "Access denied",
            status,
            detail
        }));
    }

    // Constant-time comparison prevents timing attacks (different lengths → false).
    private static bool FixedTimeEquals(string a, string b)
        => CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));
}
```

### 3. DI registration

No `FallbackPolicy` — authorization is declared **explicitly on each endpoint**
(see step 5). `AddAuthorization()` stays simple.

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
            .Validate(o => o.ApiKeys.Count > 0, "Security: at least one API Key.")
            .ValidateOnStart();

        services.AddAuthentication(ApiKeyAuthenticationHandler.SchemeName)
            .AddScheme<AuthenticationSchemeOptions, ApiKeyAuthenticationHandler>(
                ApiKeyAuthenticationHandler.SchemeName, _ => { });

        services.AddAuthorization();   // protection is explicit per endpoint

        return services;
    }
}
```

### 4. Pipeline (`Program.cs`)

```csharp
builder.Services.AddApiKeyAuth(builder.Configuration);
// ...
app.UseAuthentication();
app.UseAuthorization();   // before MapEndpoints
```

### 5. Explicit authorization per endpoint

Each endpoint declares its intent — protected with `.RequireAuthorization()`,
public with `.AllowAnonymous()`. The semantics are visible in the mapping. See
[how-to-add-endpoint](how-to-add-endpoint.md).

```csharp
// Protected: requires X-Api-Key
app.MapGet("api/v1/widgets/{id:guid}", handler)
   .RequireAuthorization();

// Public
app.MapGet("/", () => Results.Ok(/* health/info */))
   .AllowAnonymous();
```

> ⚠️ **Trade-off of the explicit choice:** without `FallbackPolicy`, an endpoint
> **without** `.RequireAuthorization()` is **open**. We gain semantic clarity, but the
> responsibility falls on the author — consider an **integration test** that ensures
> 401 on sensitive routes without a credential. (Health checks and OpenAPI stay public
> by default, which is usually what you want.)

### Accessing the caller (`IUserContext`)

The handler issues the `client_id` as a **claim** on `HttpContext.User`. For the
UseCases to access the caller **without knowing `HttpContext`**, expose an
`IUserContext` abstraction in the [Application](application-layer.md) layer, implemented in the
[Infra](infra-layer.md) layer by reading the claim.

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
    // Reads from the ClaimsPrincipal populated by the handler — NOT from HttpContext.Items.
    public string ClientId =>
        accessor.HttpContext?.User.FindFirstValue("client_id")
        ?? throw new UnauthorizedAccessException("Operation requires an authenticated ClientId.");
}
```

Registration (in the Infra DI):

```csharp
services.AddHttpContextAccessor();              // required to read the HttpContext
services.AddScoped<IUserContext, UserContext>();
```

Usage in a UseCase:

```csharp
public sealed class CreateWidgetUseCase(IUserContext userContext, /* ... */)
{
    public async Task<Result<...>> Execute(...)
    {
        var clientId = userContext.ClientId;   // who called (auditing, scoping, ...)
        // ...
    }
}
```

> The `throw` in the getter is **defensive**: on an endpoint with `.RequireAuthorization()`, the
> `client_id` will always be present. It protects against misuse in an unauthenticated
> context. The same `client_id` enriches the Serilog logs (see
> [logging-observability](logging-observability.md)).

---

## Secrets

- **Never** commit real keys to version control. `appsettings.json` carries only placeholders.
- Dev: **user-secrets**. Production: **environment variables** (App Service) or,
  preferably, **Key Vault** (referenced from the app settings).
- Rotation: since keys are a **list**, you can rotate without downtime
  (add the new one, migrate the clients, remove the old one).

## HTTPS

Keep `app.UseHttpsRedirection()`. For an internal API behind a gateway/Front Door
with TLS termination, adjust to the topology, but do **not** transmit the key over
an unencrypted channel.

## Migrating to JWT (when opening up to frontend/third parties)

The structure does not change: swap the authentication **scheme** for
`AddAuthentication().AddJwtBearer(...)`, configuring `Authority`/`Audience` and
signature validation (the app **validates** the token, it does not issue it). Everything
else (explicit authorization per endpoint, `[AllowAnonymous]`, claims, `ProblemDetails`)
remains.

## Principles

- **Explicit authorization per endpoint** (`.RequireAuthorization()` / `.AllowAnonymous()`)
  — the intent is visible in the mapping; cover sensitive routes with tests.
- **Native authentication scheme**, not standalone middleware — integrates with
  `[Authorize]`, claims and `HttpContext.User`.
- **Rejection via `ProblemDetails`** (401/403), not via exception.
- **Missing _or_ invalid API Key → 401**; **403** only for denied authorization.
- **Access the caller via `IUserContext`** (reads the `client_id` claim), not `HttpContext.Items`.
- **Constant-time comparison** and boot-time validation (`[ValidateEnumeratedItems]`
  + `ValidateOnStart`).
- **Secrets out of version control**.
- **Confirm the current** authentication/authorization API via Context7 / Microsoft Learn.
