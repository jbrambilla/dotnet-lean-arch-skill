---
tags: [arquitetura, dotnet, pattern, integracao, refit, resiliencia, http]
aliases: [Integração com Serviço Externo, Serviços Externos, Refit, ACL HTTP]
---

# 🔌 Integração com Serviço Externo

> Isola integrações com APIs externas na Infra. **Refit** para o transporte HTTP,
> **Anti-Corruption Layer (ACL)** para traduzir os contratos externos em DTOs da
> Application, **resiliência nativa** (.NET) para falhas de rede, e **`Result<T>`
> na fronteira** — a falha de integração vira um `Error`, não uma exceção que
> sobe pelo domínio.

Ver também: [index](index.md) · [camada-infra](camada-infra.md) · [camada-application](camada-application.md) · [result-pattern](result-pattern.md) · [configuracao-tipada](configuracao-tipada.md) · [logging-observabilidade](logging-observabilidade.md)

## Princípios de design

- **Refit não vaza:** a interface Refit e os DTOs de transporte são `internal` na
  Infra. A Application só conhece a abstração `IXxxGateway` e seus DTOs próprios.
- **ACL sempre:** o objeto que a API externa devolve **nunca** transita pelas
  regras de negócio. Um `Mapper` o traduz para um DTO da Application.
- **Falha vira `Result`:** o gateway captura `ApiException`/exceções e devolve
  `Result<T>` com um `Error` — coerente com o [result-pattern](result-pattern.md). Nada de `throw`
  cruzando a fronteira para a Application.
- **Resiliência por padrão:** `AddStandardResilienceHandler()` (Polly v8) cobre
  retry, circuit breaker, timeout e rate limiter.

## Estrutura de pastas

```
Infra/
└── ExternalServices/
    ├── DependencyInjection.cs          # AddExternalServices: compõe os providers
    ├── LoggingDelegatingHandler.cs     # log HTTP global, com redação de PII/segredos
    ├── ApiExceptionExtensions.cs       # ApiException -> Error (Result)
    └── <Provedor>/                     # ex.: Acme
        ├── IAcmeApi.cs                 # contrato Refit (internal)
        ├── AcmeOptions.cs              # Options (internal), ValidateOnStart
        ├── AcmeClient.cs               # implementa IXxxGateway (internal sealed)
        ├── AcmeTokenManager.cs         # (se a API usa JWT) cache + renovação
        ├── Handlers/
        │   └── AcmeAuthDelegatingHandler.cs
        └── Operations/<Operacao>/
            ├── <Operacao>Request.cs    # DTO de envio (internal)
            ├── <Operacao>Response.cs   # DTO de retorno (internal)
            └── <Operacao>Mapper.cs     # ACL: Response -> DTO da Application
```

## Packages

Confirme as últimas versões via Context7 / Microsoft Learn (ver [stack-e-dependencias](stack-e-dependencias.md)).

```
Refit.HttpClientFactory              # AddRefitClient + integração com IHttpClientFactory
Microsoft.Extensions.Http.Resilience # AddStandardResilienceHandler (Polly v8)
# System.IdentityModel.Tokens.Jwt    # só se houver TokenManager lendo expiração do JWT
```

---

## 1. Abstração na Application

O contrato e os DTOs de fronteira vivem na **Application** (`Abstractions/ExternalServices/<Recurso>/`).
Essa é a única superfície que o resto da aplicação enxerga.

```csharp
using Blueprint.Domain.Shared;

namespace Blueprint.Application.Abstractions.ExternalServices.Pagamentos;

public interface IPagamentoGateway
{
    Task<Result<Pagamento>> Obter(ObterPagamentoInput input, CancellationToken ct = default);
}

public sealed record ObterPagamentoInput(string Documento);

// DTO da Application — resultado da ACL, independente do contrato externo.
public sealed record Pagamento(string Id, decimal Valor, string Status)
{
    public static Pagamento Vazio => new(string.Empty, 0, "DESCONHECIDO");
}
```

## 2. Contrato Refit (`internal`)

```csharp
using Refit;
using Blueprint.Infra.ExternalServices.Acme.Operations.ObterPagamento;

namespace Blueprint.Infra.ExternalServices.Acme;

internal interface IAcmeApi
{
    [Get("/v1/pagamentos/{id}")]
    Task<ObterPagamentoResponse> ObterPagamento(string id, CancellationToken ct = default);
}
```

## 3. Options por provider (`internal`, validado no boot)

```csharp
using System.ComponentModel.DataAnnotations;

namespace Blueprint.Infra.ExternalServices.Acme;

internal sealed class AcmeOptions
{
    public const string SectionName = "ExternalServices:Acme";

    [Required(AllowEmptyStrings = false, ErrorMessage = "Acme: BaseUrl é obrigatório.")]
    public string BaseUrl { get; set; } = string.Empty;

    [Required(AllowEmptyStrings = false, ErrorMessage = "Acme: ApiKey é obrigatória.")]
    public string ApiKey { get; set; } = string.Empty;
}
```

> Ver [configuracao-tipada](configuracao-tipada.md). Segredos (ApiKey, senhas) **não** vão no
> `appsettings.json` versionado — use user-secrets/variáveis de ambiente.

## 4. Implementação do gateway (ACL + `Result`)

`internal sealed`, implementa a abstração da Application. Mapeia entrada, chama a
API, traduz a resposta (ACL) e **converte qualquer falha em `Result`**.

```csharp
using Microsoft.Extensions.Logging;
using Refit;
using Blueprint.Application.Abstractions.ExternalServices.Pagamentos;
using Blueprint.Domain.Shared;
using Blueprint.Infra.ExternalServices.Acme.Operations.ObterPagamento;

namespace Blueprint.Infra.ExternalServices.Acme;

internal sealed class AcmeClient(
    IAcmeApi api,
    ILogger<AcmeClient> logger) : IPagamentoGateway
{
    public async Task<Result<Pagamento>> Obter(ObterPagamentoInput input, CancellationToken ct = default)
    {
        try
        {
            var response = await api.ObterPagamento(input.Documento, ct);

            if (response.TemErro)
            {
                logger.LogWarning("Acme retornou erro de negócio: {Mensagem}", response.Mensagem);
                return Error.Failure($"Acme: {response.Mensagem}");
            }

            return response.ToPagamento();   // ACL
        }
        catch (ApiException apiEx)
        {
            // Não logamos apiEx.Content cru aqui para evitar PII — o LoggingDelegatingHandler já
            // registrou o corpo sanitizado. Logamos só status/contexto.
            logger.LogError(apiEx, "Falha de comunicação com Acme. Status: {Status}", apiEx.StatusCode);
            return apiEx.MapToError<Pagamento>();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Erro inesperado na integração com Acme.");
            return Error.Failure($"Erro inesperado na integração com Acme: {ex.Message}");
        }
    }
}
```

## 5. Tradução `ApiException` → `Error`

Centraliza o mapeamento status HTTP → [`Error`](result-pattern.md). Com os 4 tipos
atuais do blueprint (`Failure/NotFound/Conflict/Validation`):

```csharp
using System.Net;
using Refit;
using Blueprint.Domain.Shared;

namespace Blueprint.Infra.ExternalServices;

internal static class ApiExceptionExtensions
{
    public static Result<T> MapToError<T>(this ApiException ex) => ex.StatusCode switch
    {
        HttpStatusCode.NotFound => Error.NotFound("Recurso não encontrado no provedor externo."),
        HttpStatusCode.Conflict => Error.Conflict("Conflito reportado pelo provedor externo."),

        // Transitórios (5xx/timeout/429): já passaram pelo retry do resilience.
        HttpStatusCode.RequestTimeout
            or HttpStatusCode.TooManyRequests
            or HttpStatusCode.ServiceUnavailable
            or HttpStatusCode.InternalServerError
            => Error.Failure($"Provedor externo indisponível (status {(int)ex.StatusCode})."),

        _ => Error.Failure($"Erro de integração (status {(int?)ex.StatusCode}).")
    };
}
```

> ### 🔧 Extensão opcional: `ErrorType.Transient` + `Code`
> Quando as integrações crescerem, vale distinguir **falha transitória** (o caller
> pode reenfileirar/retentar mais tarde) e carregar um **`code`** de origem
> (ex.: `"ExternalServices.Acme"`) para observabilidade. Isso significa:
> - adicionar `Transient` ao `ErrorType` (mapeado para **HTTP 503** no
>   `ResultExtensions`) e um campo `Code` opcional ao `Error`;
> - `MapToError` passa a devolver `Error.Transient(code, ...)` para 5xx/timeout.
>
> **Não faz parte do core do blueprint hoje** (decisão de manter o `Error`
> enxuto) — adote por projeto se a malha de integrações justificar.

## 6. Operations (ACL): Request, Response, Mapper

DTOs de transporte são **`internal`** (não vazam). O `Mapper` faz a tradução.

```csharp
using System.Text.Json.Serialization;

namespace Blueprint.Infra.ExternalServices.Acme.Operations.ObterPagamento;

internal sealed record ObterPagamentoResponse(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("valor")] decimal Valor,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("erro")] bool TemErro,
    [property: JsonPropertyName("mensagem")] string? Mensagem);
```

```csharp
using Blueprint.Application.Abstractions.ExternalServices.Pagamentos;

namespace Blueprint.Infra.ExternalServices.Acme.Operations.ObterPagamento;

internal static class ObterPagamentoMapper
{
    public static Pagamento ToPagamento(this ObterPagamentoResponse r)
        => new(r.Id, r.Valor, r.Status);
}
```

> O mapper pode lançar se um campo essencial vier nulo — o `try/catch` genérico do
> gateway o converte em `Error.Failure`. Para contratos instáveis, prefira validar
> e devolver `Result` explicitamente.

---

## 7. DelegatingHandlers

### 7a. Autenticação por header (padrão canônico)

Injeta o token (via [9. TokenManager (JWT)](#9-tokenmanager-jwt)) em toda requisição. Registrado
como **`Transient`**.

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

> **Variação — credenciais no corpo:** algumas APIs legadas exigem usuário/senha
> **no body** (não em header). Nesse caso o handler lê o JSON, injeta um nó `auth`
> e reserializa o conteúdo. Funciona, mas acopla o handler ao formato do payload e
> tem custo de (de)serialização — use só quando a API obrigar, e mantenha o handler
> tolerante à ausência de propriedades esperadas.

### 7b. Logging HTTP global (com redação de PII/segredos)

Handler único compartilhado por todos os providers. **Redige campos sensíveis** e
**trunca** o corpo. Registrado como `Transient`.

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
        "senha", "password", "secret", "usuario", "username",
        "apikey", "api_key", "token", "accesstoken", "authorization",
        "clientsecret", "auth", "chave", "credentials", "key"
    };

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var rawBody = request.Content is not null
            ? await request.Content.ReadAsStringAsync(cancellationToken)
            : string.Empty;

        logger.LogInformation("API Externa → {Method} {Uri} | Body: {Body}",
            request.Method, request.RequestUri, SanitizeAndTruncate(rawBody));

        var response = await base.SendAsync(request, cancellationToken);

        if (response.IsSuccessStatusCode)
        {
            logger.LogInformation("API Externa ← [OK] {Method} {Uri} | {Status}",
                request.Method, request.RequestUri, (int)response.StatusCode);
        }
        else
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            logger.LogWarning("API Externa ← [FALHA] {Method} {Uri} | {Status} | {Body}",
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
        catch (JsonException) { return false; }   // não-JSON: loga como veio
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
           : string.Concat(v.AsSpan(0, MaxBodyLength), $"... [truncado: {v.Length} chars]");
}
```

> **Limitações conhecidas** (evoluir se necessário): a redação cobre objeto JSON
> raiz e objetos aninhados, **não** arrays na raiz nem **query string** da URL.
> O `Authorization` vai no header (não logado), então o token não vaza — mas
> cuidado com apikeys em query. Ler o corpo tem custo; evite em payloads enormes.

### Ordem dos handlers importa

A pipeline executa na **ordem de registro** na ida e na **ordem inversa** na volta.
Padrão deste blueprint:

```
Auth → Logging → [Resilience → socket]
```

- **Auth primeiro:** o token é resolvido uma vez por request lógico.
- **Logging acima do resilience:** loga **1 request e a resposta final** — menos
  ruído. (Se precisar enxergar **cada retry**, mova o logging para depois do
  resilience; em troca de mais volume de log.)

---

## 8. Resiliência (Polly v8)

`AddStandardResilienceHandler()` monta, nesta ordem, uma pipeline de 5 camadas:

1. **Rate limiter** — limita chamadas concorrentes.
2. **Total request timeout** — teto incluindo todas as tentativas.
3. **Retry** — reenvia em erros transitórios (5xx, 408, 429, timeouts).
4. **Circuit breaker** — abre o circuito se o destino estiver instável.
5. **Attempt timeout** — teto por tentativa individual.

```csharp
.AddStandardResilienceHandler(options =>
{
    options.Retry.MaxRetryAttempts = 3;
    options.Retry.BackoffType = Polly.DelayBackoffType.Exponential;
    options.CircuitBreaker.FailureRatio = 0.1;
    options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(30);
});
```

> **⚠️ Idempotência em `POST`:** o retry padrão reenvia independentemente do verbo.
> Se o `POST` **não** for idempotente (criar duplicado se chamado 2×), ajuste a
> política de retry para esse cliente ou desabilite o retry nele.

> **Default global (opcional):** os [ServiceDefaults](logging-observabilidade.md)
> podem aplicar `AddStandardResilienceHandler()` a **todos** os `HttpClient` via
> `ConfigureHttpClientDefaults` — assim cada provider não precisa repetir.

---

## 9. TokenManager (JWT)

Para APIs com **OAuth/JWT**: cacheia o token, renova só quando perto de expirar
(buffer), com `SemaphoreSlim` + double-check para thread-safety. Registrado como
**Singleton** (mantém o token entre requests).

> **Por que a versão robusta:** um Singleton **não deve injetar o client Refit de
> auth diretamente** — isso "prende" o `HttpMessageHandler` e impede a reciclagem
> do `IHttpClientFactory` (staleness de DNS em apps longevas). A solução: resolver
> o client de auth **sob demanda** via `IServiceScopeFactory`.

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
        if (IsValid(_token)) return _token!;            // fast path, sem lock

        await _gate.WaitAsync(ct);
        try
        {
            if (IsValid(_token)) return _token!;        // double-check

            // Resolve o client de auth sob demanda — handler reciclado pelo factory.
            using var scope = scopeFactory.CreateScope();
            var authApi = scope.ServiceProvider.GetRequiredService<IAcmeAuthApi>();

            var resposta = await authApi.Autenticar(ct);
            _token = resposta.AccessToken;
            return _token;
        }
        catch
        {
            _token = null;                              // força nova tentativa depois
            throw;
        }
        finally
        {
            _gate.Release();
        }
    }

    // Lê a expiração do payload localmente (sem validar assinatura — confiamos na origem).
    private static bool IsValid(string? token)
    {
        if (string.IsNullOrEmpty(token) || !_handler.CanReadToken(token)) return false;
        return _handler.ReadJwtToken(token).ValidTo > DateTime.UtcNow.AddMinutes(1); // buffer
    }

    public void Dispose() => _gate.Dispose();
}
```

> **Buffer de expiração** (`AddMinutes(1)`): evita usar um token que pode expirar
> *durante* a requisição. JWT usa `exp` em UTC — por isso `DateTime.UtcNow`.

---

## 10. Registro no DI (por provider)

Um ponto de extensão `AddExternalServices` compõe os providers; cada provider tem
seu `AddXxx`. O handler de logging é registrado uma vez e reutilizado.

```csharp
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Refit;
using Blueprint.Application.Abstractions.ExternalServices.Pagamentos;
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

        // Client de autenticação (token) — usa ApiKey estática.
        services.AddRefitClient<IAcmeAuthApi>()
            .ConfigureHttpClient((sp, c) =>
            {
                var o = sp.GetRequiredService<IOptions<AcmeOptions>>().Value;
                c.BaseAddress = new Uri(o.BaseUrl);
                c.DefaultRequestHeaders.Add("X-Api-Key", o.ApiKey);
            })
            .AddHttpMessageHandler<LoggingDelegatingHandler>()
            .AddStandardResilienceHandler();

        // Client de negócio — JWT injetado pelo AuthDelegatingHandler.
        services.AddRefitClient<IAcmeApi>()
            .ConfigureHttpClient((sp, c) =>
            {
                var o = sp.GetRequiredService<IOptions<AcmeOptions>>().Value;
                c.BaseAddress = new Uri(o.BaseUrl);
            })
            .AddHttpMessageHandler<AcmeAuthDelegatingHandler>()   // 1º
            .AddHttpMessageHandler<LoggingDelegatingHandler>()    // 2º (acima do resilience)
            .AddStandardResilienceHandler();                      // 3º (mais interno)

        services.AddScoped<IPagamentoGateway, AcmeClient>();
        return services;
    }
}
```

> `AddExternalServices` é chamado pelo `AddInfrastructure` da Infra (ver [camada-infra](camada-infra.md)).

## Segurança

- **Segredos fora do versionamento** (user-secrets / variáveis de ambiente).
- **Redação de PII/segredos no log** (LoggingDelegatingHandler) — revise o conjunto
  `SensitiveFields` por projeto e cuide de apikeys em query string.
- **Não logue `ApiException.Content` cru** no gateway — pode conter dados sensíveis.

## Princípios

- **Refit + DTOs `internal`**; só `IXxxGateway` + DTOs da Application são públicos.
- **ACL obrigatória** — contrato externo nunca entra nas regras de negócio.
- **Gateway devolve `Result<T>`**, nunca relança para a Application.
- **Resiliência via `AddStandardResilienceHandler`**; cuidado com `POST` não idempotente.
- **Auth por header + TokenManager Singleton resolvendo o client sob demanda.**
- **Logging acima do resilience** (1 log por request lógico) com redação de segredos.
- **Confirme a API atual** de Refit/Polly/resilience via Context7 / Microsoft Learn.
