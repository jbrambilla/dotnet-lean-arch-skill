---
tags: [architecture, dotnet, pattern, integration, refit, resilience, http]
aliases: [External Service Integration, External Services, Refit, HTTP ACL]
---

# 🔌 External Service Integration

> Isolates integrations with external APIs in Infra. **Refit** for HTTP transport,
> **anti-corruption layer (ACL)** to translate external contracts into Application
> DTOs, **native resilience** (.NET) for network failures, and **`Result<T>` at
> the boundary** — an integration failure becomes an `Error`, not an exception
> bubbling up through the domain.

See also: [index](index.md) · [infra-layer](infra-layer.md) · [application-layer](application-layer.md) · [result-pattern](result-pattern.md) · [typed-configuration](typed-configuration.md) · [logging-observability](logging-observability.md)

## Design principles

- **Refit does not leak:** the Refit interface and transport DTOs are `internal` in
  Infra. The Application only knows the `IXxxGateway` abstraction and its own DTOs.
- **ACL always:** the object returned by the external API **never** flows through
  business rules. A `Mapper` translates it into an Application DTO.
- **Failure becomes `Result`:** the gateway catches `ApiException`/exceptions and
  returns `Result<T>` with an `Error` — consistent with the [result-pattern](result-pattern.md). No `throw`
  crossing the boundary into the Application.
- **Resilience by default:** `AddStandardResilienceHandler()` (Polly v8) covers
  retry, circuit breaker, timeout, and rate limiter.

## Folder structure

```
Infra/
└── ExternalServices/
    ├── DependencyInjection.cs          # AddExternalServices: composes the providers
    ├── LoggingDelegatingHandler.cs     # global HTTP logging, with PII/secret redaction
    ├── ApiExceptionExtensions.cs       # ApiException -> Error (Result)
    └── <Provider>/                     # e.g.: Acme
        ├── IAcmeApi.cs                 # Refit contract (internal)
        ├── AcmeOptions.cs              # Options (internal), ValidateOnStart
        ├── AcmeClient.cs               # implements IXxxGateway (internal sealed)
        ├── AcmeTokenManager.cs         # (if the API uses JWT) caching + renewal
        ├── Handlers/
        │   └── AcmeAuthDelegatingHandler.cs
        └── Operations/<Operation>/
            ├── <Operation>Request.cs   # outbound DTO (internal)
            ├── <Operation>Response.cs  # inbound DTO (internal)
            └── <Operation>Mapper.cs    # ACL: Response -> Application DTO
```

## Packages

Confirm the latest versions via Context7 / Microsoft Learn (see [stack-and-dependencies](stack-and-dependencies.md)).

```
Refit.HttpClientFactory              # AddRefitClient + IHttpClientFactory integration
Microsoft.Extensions.Http.Resilience # AddStandardResilienceHandler (Polly v8)
# System.IdentityModel.Tokens.Jwt    # only if there is a TokenManager reading JWT expiration
```

---

## 1. Abstraction in the Application

The contract and boundary DTOs live in the **Application** (`Abstractions/ExternalServices/<Resource>/`).
This is the only surface the rest of the application sees.

```csharp
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Abstractions.ExternalServices.Payments;

public interface IPaymentGateway
{
    Task<Result<Payment>> Get(GetPaymentInput input, CancellationToken ct = default);
}

public sealed record GetPaymentInput(string Document);

// Application DTO — the ACL output, independent of the external contract.
public sealed record Payment(string Id, decimal Amount, string Status)
{
    public static Payment Empty => new(string.Empty, 0, "UNKNOWN");
}
```

## 2. Refit contract (`internal`)

```csharp
using Refit;
using Blueprint.Infra.ExternalServices.Acme.Operations.GetPayment;

namespace Blueprint.Infra.ExternalServices.Acme;

internal interface IAcmeApi
{
    [Get("/v1/payments/{id}")]
    Task<GetPaymentResponse> GetPayment(string id, CancellationToken ct = default);
}
```

## 3. Options per provider (`internal`, validated at boot)

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Infra.ExternalServices.Acme;

internal sealed class AcmeOptions
{
    public const string SectionName = "ExternalServices:Acme";

    [Required(AllowEmptyStrings = false, ErrorMessage = "Acme: BaseUrl is required.")]
    public string BaseUrl { get; set; } = string.Empty;

    [Required(AllowEmptyStrings = false, ErrorMessage = "Acme: ApiKey is required.")]
    public string ApiKey { get; set; } = string.Empty;
}
```

> See [typed-configuration](typed-configuration.md). Secrets (ApiKey, passwords) do **not** go into
> the versioned `appsettings.json` — use user-secrets/environment variables.

## 4. Gateway implementation (ACL + `Result`)

`internal sealed`, implements the Application abstraction. Maps the input, calls
the API, translates the response (ACL), and **converts any failure into `Result`**.

```csharp
using Microsoft.Extensions.Logging;
using Refit;
using Blueprint.Application.Abstractions.ExternalServices.Payments;
using Blueprint.Domain.Shared;
using Blueprint.Infra.ExternalServices.Acme.Operations.GetPayment;

namespace Blueprint.Infra.ExternalServices.Acme;

internal sealed class AcmeClient(
    IAcmeApi api,
    ILogger<AcmeClient> logger) : IPaymentGateway
{
    public async Task<Result<Payment>> Get(GetPaymentInput input, CancellationToken ct = default)
    {
        try
        {
            var response = await api.GetPayment(input.Document, ct);

            if (response.HasError)
            {
                logger.LogWarning("Acme returned a business error: {Message}", response.Message);
                return Error.Failure($"Acme: {response.Message}");
            }

            return response.ToPayment();   // ACL
        }
        catch (ApiException apiEx)
        {
            // We don't log raw apiEx.Content here to avoid PII — the LoggingDelegatingHandler already
            // recorded the sanitized body. We log only status/context.
            logger.LogError(apiEx, "Communication failure with Acme. Status: {Status}", apiEx.StatusCode);
            return apiEx.MapToError<Payment>();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error in the Acme integration.");
            return Error.Failure($"Unexpected error in the Acme integration: {ex.Message}");
        }
    }
}
```

## 5. `ApiException` → `Error` translation

Centralizes the HTTP status → [`Error`](result-pattern.md) mapping. With the blueprint's
current 4 types (`Failure/NotFound/Conflict/Validation`):

```csharp
using System.Net;
using Refit;
using Blueprint.Domain.Shared;

namespace Blueprint.Infra.ExternalServices;

internal static class ApiExceptionExtensions
{
    public static Result<T> MapToError<T>(this ApiException ex) => ex.StatusCode switch
    {
        HttpStatusCode.NotFound => Error.NotFound("Resource not found at the external provider."),
        HttpStatusCode.Conflict => Error.Conflict("Conflict reported by the external provider."),

        // Transient (5xx/timeout/429): already went through the resilience retry.
        HttpStatusCode.RequestTimeout
            or HttpStatusCode.TooManyRequests
            or HttpStatusCode.ServiceUnavailable
            or HttpStatusCode.InternalServerError
            => Error.Failure($"External provider unavailable (status {(int)ex.StatusCode})."),

        _ => Error.Failure($"Integration error (status {(int?)ex.StatusCode}).")
    };
}
```

> ### 🔧 Optional extension: `ErrorType.Transient` + `Code`
> As integrations grow, it becomes worth distinguishing **transient failure** (the
> caller can re-enqueue/retry later) and carrying an origin **`code`**
> (e.g.: `"ExternalServices.Acme"`) for observability. This means:
> - adding `Transient` to `ErrorType` (mapped to **HTTP 503** in
>   `ResultExtensions`) and an optional `Code` field to `Error`;
> - `MapToError` starts returning `Error.Transient(code, ...)` for 5xx/timeout.
>
> **Not part of the blueprint's core today** (a decision to keep `Error`
> lean) — adopt per project if the integration mesh justifies it.

## 6. Operations (ACL): Request, Response, Mapper

Transport DTOs are **`internal`** (they don't leak). The `Mapper` performs the translation.

```csharp
using System.Text.Json.Serialization;

namespace Blueprint.Infra.ExternalServices.Acme.Operations.GetPayment;

internal sealed record GetPaymentResponse(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("amount")] decimal Amount,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("error")] bool HasError,
    [property: JsonPropertyName("message")] string? Message);
```

```csharp
using Blueprint.Application.Abstractions.ExternalServices.Payments;

namespace Blueprint.Infra.ExternalServices.Acme.Operations.GetPayment;

internal static class GetPaymentMapper
{
    public static Payment ToPayment(this GetPaymentResponse r)
        => new(r.Id, r.Amount, r.Status);
}
```

> The mapper may throw if an essential field comes in null — the gateway's generic
> `try/catch` converts it into `Error.Failure`. For unstable contracts, prefer
> validating and returning `Result` explicitly.

---

## 7. DelegatingHandlers

### 7a. Header-based authentication (canonical pattern)

Injects the token (via [9. TokenManager (JWT)](#9-tokenmanager-jwt)) into every request. Registered
as **`Transient`**.

```csharp
using System.Net.Http.Headers;

namespace Blueprint.Infra.ExternalServices.Acme.Handlers;

internal sealed class AcmeAuthDelegatingHandler(IAcmeTokenManager tokenManager) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await tokenManager.GetTokenAsync(cancellationToken);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await base.SendAsync(request, cancellationToken);
    }
}
```

> **Variation — credentials in the body:** some legacy APIs require username/password
> **in the body** (not in a header). In that case the handler reads the JSON, injects
> an `auth` node, and reserializes the content. It works, but it couples the handler
> to the payload format and has (de)serialization cost — use it only when the API
> forces you to, and keep the handler tolerant to missing expected properties.

### 7b. Global HTTP logging (with PII/secret redaction)

A single handler shared by all providers. **Redacts sensitive fields** and
**truncates** the body. Registered as `Transient`.

```csharp
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging;

namespace Blueprint.Infra.ExternalServices;

internal sealed class LoggingDelegatingHandler(ILogger<LoggingDelegatingHandler> logger) : DelegatingHandler
{
    private const int MaxBodyLength = 1000;

    private static readonly HashSet<string> SensitiveFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "password", "secret", "username",
        "apikey", "api_key", "token", "accesstoken", "authorization",
        "clientsecret", "auth", "credentials", "key",
        // add the equivalents in your domain's language, e.g. pt-BR:
        "senha", "usuario", "chave"
    };

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var rawBody = request.Content is not null
            ? await request.Content.ReadAsStringAsync(cancellationToken)
            : string.Empty;

        logger.LogInformation("External API → {Method} {Uri} | Body: {Body}",
            request.Method, request.RequestUri, SanitizeAndTruncate(rawBody));

        var response = await base.SendAsync(request, cancellationToken);

        if (response.IsSuccessStatusCode)
        {
            logger.LogInformation("External API ← [OK] {Method} {Uri} | {Status}",
                request.Method, request.RequestUri, (int)response.StatusCode);
        }
        else
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            logger.LogWarning("External API ← [FAILURE] {Method} {Uri} | {Status} | {Body}",
                request.Method, request.RequestUri, (int)response.StatusCode, Truncate(errorBody));
        }

        return response;
    }

    private static string SanitizeAndTruncate(string body)
        => string.IsNullOrWhiteSpace(body) ? string.Empty
           : Truncate(TrySanitizeJson(body, out var s) ? s : body);

    private static bool TrySanitizeJson(string body, out string sanitized)
    {
        sanitized = body;
        try
        {
            if (JsonNode.Parse(body) is not JsonObject obj) return false;
            Redact(obj);
            sanitized = obj.ToJsonString();
            return true;
        }
        catch (JsonException) { return false; }   // not JSON: log as-is
    }

    private static void Redact(JsonObject obj)
    {
        foreach (var key in obj.Select(x => x.Key).ToList())
        {
            if (SensitiveFields.Contains(key)) obj[key] = "***";
            else if (obj[key] is JsonObject nested) Redact(nested);
        }
    }

    private static string Truncate(string v)
        => v.Length <= MaxBodyLength ? v
           : string.Concat(v.AsSpan(0, MaxBodyLength), $"... [truncated: {v.Length} chars]");
}
```

> **Known limitations** (evolve if needed): redaction covers the root JSON object
> and nested objects, **not** root-level arrays nor the URL **query string**.
> `Authorization` goes in the header (not logged), so the token doesn't leak — but
> watch out for API keys in the query string. Reading the body has a cost; avoid it
> for huge payloads.

### Handler order matters

The pipeline executes in **registration order** on the way out and in **reverse
order** on the way back. This blueprint's default:

```
Auth → Logging → [Resilience → socket]
```

- **Auth first:** the token is resolved once per logical request.
- **Logging above resilience:** logs **1 request and the final response** — less
  noise. (If you need to see **each retry**, move logging below the resilience
  handler; in exchange for more log volume.)

---

## 8. Resilience (Polly v8)

`AddStandardResilienceHandler()` builds, in this order, a 5-layer pipeline:

1. **Rate limiter** — limits concurrent calls.
2. **Total request timeout** — cap including all attempts.
3. **Retry** — resends on transient errors (5xx, 408, 429, timeouts).
4. **Circuit breaker** — opens the circuit if the target is unstable.
5. **Attempt timeout** — cap per individual attempt.

```csharp
.AddStandardResilienceHandler(options =>
{
    options.Retry.MaxRetryAttempts = 3;
    options.Retry.BackoffType = Polly.DelayBackoffType.Exponential;
    options.CircuitBreaker.FailureRatio = 0.1;
    options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(30);
});
```

> **⚠️ Idempotency on `POST`:** the default retry resends regardless of the verb.
> If the `POST` is **not** idempotent (creates a duplicate if called twice), adjust
> the retry policy for that client or disable retry on it.

> **Global default (optional):** the [ServiceDefaults](logging-observability.md)
> can apply `AddStandardResilienceHandler()` to **all** `HttpClient` instances via
> `ConfigureHttpClientDefaults` — so each provider doesn't need to repeat it.

---

## 9. TokenManager (JWT)

For APIs with **OAuth/JWT**: caches the token, renews only when close to expiring
(buffer), with `SemaphoreSlim` + double-check for thread-safety. Registered as
**Singleton** (keeps the token across requests).

> **Why the robust version:** a Singleton **must not inject the auth Refit client
> directly** — that "pins" the `HttpMessageHandler` and prevents `IHttpClientFactory`
> recycling (DNS staleness in long-lived apps). The solution: resolve the auth
> client **on demand** via `IServiceScopeFactory`.

```csharp
using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.DependencyInjection;

namespace Blueprint.Infra.ExternalServices.Acme;

internal interface IAcmeTokenManager
{
    Task<string> GetTokenAsync(CancellationToken ct = default);
}

internal sealed class AcmeTokenManager(IServiceScopeFactory scopeFactory) : IAcmeTokenManager, IDisposable
{
    private string? _token;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private static readonly JwtSecurityTokenHandler _handler = new();

    public async Task<string> GetTokenAsync(CancellationToken ct = default)
    {
        if (IsValid(_token)) return _token!;            // fast path, no lock

        await _gate.WaitAsync(ct);
        try
        {
            if (IsValid(_token)) return _token!;        // double-check

            // Resolve the auth client on demand — handler recycled by the factory.
            using var scope = scopeFactory.CreateScope();
            var authApi = scope.ServiceProvider.GetRequiredService<IAcmeAuthApi>();

            var response = await authApi.Authenticate(ct);
            _token = response.AccessToken;
            return _token;
        }
        catch
        {
            _token = null;                              // forces a new attempt later
            throw;
        }
        finally
        {
            _gate.Release();
        }
    }

    // Reads the expiration from the payload locally (without validating the signature — we trust the source).
    private static bool IsValid(string? token)
    {
        if (string.IsNullOrEmpty(token) || !_handler.CanReadToken(token)) return false;
        return _handler.ReadJwtToken(token).ValidTo > DateTime.UtcNow.AddMinutes(1); // buffer
    }

    public void Dispose() => _gate.Dispose();
}
```

> **Expiration buffer** (`AddMinutes(1)`): avoids using a token that may expire
> *during* the request. JWT uses `exp` in UTC — hence `DateTime.UtcNow`.

---

## 10. DI registration (per provider)

An `AddExternalServices` extension point composes the providers; each provider has
its own `AddXxx`. The logging handler is registered once and reused.

```csharp
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Refit;
using Blueprint.Application.Abstractions.ExternalServices.Payments;
using Blueprint.Infra.ExternalServices.Acme;
using Blueprint.Infra.ExternalServices.Acme.Handlers;

namespace Blueprint.Infra.ExternalServices;

public static class DependencyInjection
{
    public static IServiceCollection AddExternalServices(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddTransient<LoggingDelegatingHandler>();
        services.AddAcme(configuration);
        return services;
    }

    private static IServiceCollection AddAcme(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<AcmeOptions>()
            .Bind(configuration.GetSection(AcmeOptions.SectionName))
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddSingleton<IAcmeTokenManager, AcmeTokenManager>();
        services.AddTransient<AcmeAuthDelegatingHandler>();

        // Authentication (token) client — uses a static ApiKey.
        services.AddRefitClient<IAcmeAuthApi>()
            .ConfigureHttpClient((sp, c) =>
            {
                var o = sp.GetRequiredService<IOptions<AcmeOptions>>().Value;
                c.BaseAddress = new Uri(o.BaseUrl);
                c.DefaultRequestHeaders.Add("X-Api-Key", o.ApiKey);
            })
            .AddHttpMessageHandler<LoggingDelegatingHandler>()
            .AddStandardResilienceHandler();

        // Business client — JWT injected by the AuthDelegatingHandler.
        services.AddRefitClient<IAcmeApi>()
            .ConfigureHttpClient((sp, c) =>
            {
                var o = sp.GetRequiredService<IOptions<AcmeOptions>>().Value;
                c.BaseAddress = new Uri(o.BaseUrl);
            })
            .AddHttpMessageHandler<AcmeAuthDelegatingHandler>()   // 1st
            .AddHttpMessageHandler<LoggingDelegatingHandler>()    // 2nd (above resilience)
            .AddStandardResilienceHandler();                      // 3rd (innermost)

        services.AddScoped<IPaymentGateway, AcmeClient>();
        return services;
    }
}
```

> `AddExternalServices` is called by Infra's `AddInfrastructure` (see [infra-layer](infra-layer.md)).

## Security

- **Secrets out of version control** (user-secrets / environment variables).
- **PII/secret redaction in logs** (LoggingDelegatingHandler) — review the
  `SensitiveFields` set per project and watch for API keys in the query string.
- **Never log raw `ApiException.Content`** in the gateway — it may contain sensitive data.

## Principles

- **Refit + `internal` DTOs**; only `IXxxGateway` + Application DTOs are public.
- **ACL is mandatory** — the external contract never enters business rules.
- **The gateway returns `Result<T>`**, never rethrows to the Application.
- **Resilience via `AddStandardResilienceHandler`**; watch out for non-idempotent `POST`.
- **Header-based auth + Singleton TokenManager resolving the client on demand.**
- **Logging above resilience** (1 log per logical request) with secret redaction.
- **Confirm the current API** of Refit/Polly/resilience via Context7 / Microsoft Learn.
