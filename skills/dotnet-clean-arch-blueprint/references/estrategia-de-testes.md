---
tags: [arquitetura, dotnet, testes, testcontainers, integracao, xunit]
aliases: [Estratégia de Testes, Testes, TestContainers]
---

# 🧪 Estratégia de Testes

> Dois níveis: **testes unitários de domínio** (rápidos, sem infraestrutura) e
> **testes de integração de UseCase** com banco real via **TestContainers**. A
> meta da integração é ser **fiel ao caso de uso**: roda o UseCase de verdade,
> contra um PostgreSQL real, mockando só o que cruza a fronteira do processo.

Ver também: [index](index.md) · [camada-application](camada-application.md) · [result-pattern](result-pattern.md) · [stack-e-dependencias](stack-e-dependencias.md) · [configuracao-tipada](configuracao-tipada.md)

## Pirâmide pragmática

| Nível | O que cobre | Infra | Velocidade |
| ----- | ----------- | ----- | ---------- |
| **Unitário de domínio** | invariantes de entidades, value objects, regras puras | nenhuma | ⚡ instantâneo |
| **Integração de UseCase** | fluxo do UseCase + persistência (EF Core + banco real) | container PostgreSQL | 🐢 segundos |

> Não busque cobrir tudo em integração. Regra de domínio testa-se barato no
> nível unitário; a integração foca no comportamento ponta-a-ponta do UseCase.

## Packages

Confirme as **últimas versões** via Context7 / Microsoft Learn (ver
[stack-e-dependencias](stack-e-dependencias.md)) — a API do xUnit e do Testcontainers muda entre majors.

```
# Runner / SDK
Microsoft.NET.Test.Sdk
xunit
xunit.runner.visualstudio

# Host de teste da API
Microsoft.AspNetCore.Mvc.Testing

# Container + reset de banco
Testcontainers.PostgreSql
Respawn

# Asserts + mocks
Shouldly        # FluentAssertions virou pago (v8+); Shouldly é o substituto gratuito
NSubstitute
```

## Estrutura de pastas

`tests/` na raiz, espelhando `src/`:

```
tests/
├── <Sln>.UnitTests/                      # domínio, sem container
│   └── Domain/
│       └── WidgetTests.cs
└── integration/
    └── <Sln>.IntegrationTests/           # TestContainers + UseCases
        ├── Abstractions/
        │   ├── IntegrationTestWebAppFactory.cs
        │   ├── IntegrationCollection.cs
        │   └── IntegrationTestBase.cs
        ├── Data/
        │   └── TestDataSeeder.cs
        └── UseCases/<Recurso>/
            └── <Acao>Tests.cs
```

> O projeto de integração referencia o projeto **Api** (`<Sln>.Api`) — é ele que
> `WebApplicationFactory<Program>` instancia.

## Pré-requisito: `Program` acessível

Com top-level statements, a classe `Program` é `internal` e
`WebApplicationFactory<Program>` não a enxerga. Exponha-a ao fim do `Program.cs`:

```csharp
// fim do Program.cs
public partial class Program;   // necessário para o WebApplicationFactory
```

> Alternativa: `<InternalsVisibleTo Include="<Sln>.IntegrationTests" />` no `.csproj` da Api.

---

## Nível 1 — Unitário de domínio

Sem container, sem DI. Testa a construção sempre-válida (ver [camada-domain](camada-domain.md) e
[validacao-dois-niveis](validacao-dois-niveis.md)). Asserts com **Shouldly**.

```csharp
using Blueprint.Domain;
using Blueprint.Domain.Shared;
using Blueprint.Domain.ValueObjects;
using Shouldly;
using Xunit;

namespace Blueprint.UnitTests.Domain;

public class WidgetTests
{
    [Fact]
    public void Criar_DeveLancarDomainException_QuandoQuantidadeNegativa()
    {
        var acao = () => new Widget("contato@exemplo.com", "Engrenagem", -1);

        acao.ShouldThrow<DomainException>();
    }

    [Theory]
    [InlineData("")]
    [InlineData("sem-arroba")]
    public void Email_Criar_DeveLancar_QuandoFormatoInvalido(string entrada)
    {
        Should.Throw<DomainException>(() => Email.Criar(entrada));
    }

    [Fact]
    public void AlterarQuantidade_DeveAtualizar_QuandoValorValido()
    {
        var widget = new Widget("contato@exemplo.com", "Engrenagem", 1);

        widget.AlterarQuantidade(10);

        widget.Quantidade.ShouldBe(10);
    }
}
```

---

## Nível 2 — Integração com TestContainers

### A. WebApplicationFactory

Sobe **um** container PostgreSQL, aplica as migrations **reais** com
`MigrateAsync()` (zero manutenção, testa as próprias migrações) e prepara o
**Respawn** para resetar dados entre testes.

```csharp
using System.Data.Common;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using NSubstitute;
using Respawn;
using Blueprint.Application.Abstractions;
using Blueprint.Infra.Persistence;
using Testcontainers.PostgreSql;
using Xunit;

namespace Blueprint.IntegrationTests.Abstractions;

public sealed class IntegrationTestWebAppFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine")
        .Build();

    private DbConnection _connection = null!;
    private Respawner _respawner = null!;

    public async Task InitializeAsync()
    {
        await _db.StartAsync();

        // Acessar Services constrói o host (já com a connection string do container).
        using (var scope = Services.CreateScope())
        {
            var ctx = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            await ctx.Database.MigrateAsync();   // aplica as migrations reais
        }

        _connection = new NpgsqlConnection(_db.GetConnectionString());
        await _connection.OpenAsync();

        _respawner = await Respawner.CreateAsync(_connection, new RespawnerOptions
        {
            DbAdapter = DbAdapter.Postgres,
            SchemasToInclude = ["public"],
            TablesToIgnore = [new Table("__EFMigrationsHistory")]
        });
    }

    // Chamado antes de cada teste pela IntegrationTestBase.
    public async Task ResetDatabaseAsync() => await _respawner.ResetAsync(_connection);

    public new async Task DisposeAsync()
    {
        await _connection.DisposeAsync();
        await _db.DisposeAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                // Conexão aponta para o container.
                ["ConnectionStrings:app-db"] = _db.GetConnectionString(),

                // STUBS de Options — ver "Por que config in-memory" abaixo.
                ["Widget:BaseUrl"] = "https://stub.interno",
                ["Widget:Limite"] = "50",
                ["Widget:Parametros:0:Nome"] = "foo",   // sintaxe de array: Chave:Indice:Prop
                ["Widget:Parametros:0:Valor"] = "bar",
            });
        });

        builder.ConfigureTestServices(services =>
        {
            // Reaponta o DbContext para o container.
            services.RemoveAll<DbContextOptions<ApplicationDbContext>>();
            services.AddDbContext<ApplicationDbContext>(o => o.UseNpgsql(_db.GetConnectionString()));

            // Substitui dependências que cruzam a fronteira do processo por fakes.
            services.RemoveAll<INotificadorExterno>();
            services.AddSingleton(Substitute.For<INotificadorExterno>());
        });
    }
}
```

> ### Por que config in-memory?
> A app usa [Options com `ValidateOnStart()`](configuracao-tipada.md). No CI, o
> `WebApplicationFactory` **sobe a aplicação de verdade** — se faltar qualquer
> chave obrigatória, o boot falha e os testes nem rodam. Preencher **stubs** em
> memória satisfaz a validação **sem afrouxá-la**. É a forma correta de manter o
> fail-fast e ainda testar.

### B. Collection fixture — **um** container para toda a suíte

⚠️ **Ponto de atenção comum:** `IClassFixture<Factory>` cria uma factory (e um
container) **por classe de teste**. Para compartilhar **um único** container
entre todas as classes, use `ICollectionFixture<Factory>` + `[CollectionDefinition]`.
O atributo `[Collection]` também serializa a execução (evita conflito no banco).

```csharp
using Xunit;

namespace Blueprint.IntegrationTests.Abstractions;

[CollectionDefinition(IntegrationCollection.Name)]
public sealed class IntegrationCollection : ICollectionFixture<IntegrationTestWebAppFactory>
{
    public const string Name = "Integration";
}
```

### C. Base de teste

Cria um scope por teste, expõe `DbContext`/`ServiceProvider`/`DataSeeder` e, no
`InitializeAsync` (roda **antes de cada teste**), **reseta** o banco e **semeia**
o estado inicial.

```csharp
using Microsoft.Extensions.DependencyInjection;
using Blueprint.Application.Abstractions;
using Blueprint.IntegrationTests.Data;
using Xunit;

namespace Blueprint.IntegrationTests.Abstractions;

[Collection(IntegrationCollection.Name)]   // todas as classes entram na mesma collection
public abstract class IntegrationTestBase : IAsyncLifetime
{
    private readonly IServiceScope _scope;
    private readonly IntegrationTestWebAppFactory _factory;

    protected readonly IServiceProvider ServiceProvider;
    protected readonly IApplicationDbContext DbContext;
    protected readonly TestDataSeeder DataSeeder;

    protected IntegrationTestBase(IntegrationTestWebAppFactory factory)
    {
        _factory = factory;
        _scope = factory.Services.CreateScope();
        ServiceProvider = _scope.ServiceProvider;
        DbContext = ServiceProvider.GetRequiredService<IApplicationDbContext>();
        DataSeeder = new TestDataSeeder(DbContext);
    }

    public async Task InitializeAsync()
    {
        await _factory.ResetDatabaseAsync();
        await DataSeeder.SeedAsync();
    }

    public Task DisposeAsync()
    {
        _scope.Dispose();
        return Task.CompletedTask;
    }
}
```

> **xUnit v3:** `IAsyncLifetime` passou a usar `ValueTask` (e herda
> `IAsyncDisposable`). Ajuste as assinaturas conforme a versão — confirme via
> Context7 / Microsoft Learn.

### D. Seeder

Estado inicial reproduzível, com getters para o arrange dos testes.

```csharp
using Blueprint.Application.Abstractions;
using Blueprint.Domain;

namespace Blueprint.IntegrationTests.Data;

public sealed class TestDataSeeder(IApplicationDbContext dbContext)
{
    private readonly List<Widget> _widgets = [];

    public Widget GetWidget(int index = 0) => _widgets[index];

    public async Task SeedAsync()
    {
        for (var i = 0; i < 3; i++)
            _widgets.Add(new Widget($"contato{i}@exemplo.com", $"Widget {i}", i + 1));

        await dbContext.Widgets.AddRangeAsync(_widgets);
        await dbContext.SaveChangesAsync();
    }
}
```

### E. Teste de UseCase

Resolve o UseCase **do container de DI** (não instancia à mão) — assim testa o
wiring real, com as deps externas já substituídas por fakes no factory. Asserts
sobre o [`Result<T>`](result-pattern.md).

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Blueprint.Application.Features.Widgets;
using Blueprint.Domain.Shared;
using Blueprint.IntegrationTests.Abstractions;
using Shouldly;
using Xunit;

namespace Blueprint.IntegrationTests.UseCases.Widgets;

public sealed class AtualizarWidgetTests(IntegrationTestWebAppFactory factory)
    : IntegrationTestBase(factory)
{
    [Fact]
    public async Task Deve_AtualizarQuantidade_QuandoWidgetExiste()
    {
        // Arrange
        var widget = DataSeeder.GetWidget();
        var useCase = ServiceProvider.GetRequiredService<AtualizarWidgetUseCase>();
        var request = new AtualizarWidgetRequest(widget.Id, 42);

        // Act
        var resultado = await useCase.Execute(request, CancellationToken.None);

        // Assert — contrato do Result
        resultado.IsSuccess.ShouldBeTrue();
        resultado.Value!.Quantidade.ShouldBe(42);

        // Assert — persistência, em um scope NOVO (evita ler do change tracker).
        using var verifyScope = factory.Services.CreateScope();
        var ctx = verifyScope.ServiceProvider.GetRequiredService<IApplicationDbContext>();
        var persistido = await ctx.Widgets.FirstOrDefaultAsync(w => w.Id == widget.Id);

        persistido.ShouldNotBeNull();
        persistido!.Quantidade.ShouldBe(42);
    }

    [Fact]
    public async Task Deve_RetornarNotFound_QuandoWidgetNaoExiste()
    {
        var useCase = ServiceProvider.GetRequiredService<AtualizarWidgetUseCase>();

        var resultado = await useCase.Execute(
            new AtualizarWidgetRequest(Guid.NewGuid(), 1), CancellationToken.None);

        resultado.IsFailure.ShouldBeTrue();
        resultado.Error!.Type.ShouldBe(ErrorType.NotFound);
    }
}
```

> **Dica de change tracker:** o `DbContext` exposto pela base e o UseCase
> resolvido compartilham o mesmo scope/contexto. Para asserir que algo
> **persistiu de fato**, leia de um **scope novo** (como acima) — senão você pode
> estar lendo a entidade ainda rastreada em memória.

> **Verificando interações de mocks (NSubstitute):** `DidNotReceive()` /
> `Received()` precisam **encadear o método verificado** — sozinhos são no-op:
> ```csharp
> notificador.DidNotReceive().Enviar(Arg.Any<string>());   // ✅ verifica
> notificador.DidNotReceive();                              // ❌ não assere nada
> ```

## Convenção de nomenclatura de testes

`Deve_<ResultadoEsperado>_Quando<Condição>` — em português, descrevendo
comportamento, não implementação.

```
Deve_AtualizarQuantidade_QuandoWidgetExiste
Deve_RetornarNotFound_QuandoWidgetNaoExiste
Deve_LancarDomainException_QuandoQuantidadeNegativa
```

Dentro do corpo, separe **Arrange / Act / Assert** (com comentário ou linha em branco).

## Princípios

- **Banco real via TestContainers** — fidelidade > velocidade na integração.
- **`MigrateAsync()` para o schema** — testa as próprias migrations, sem manutenção.
- **Respawn entre testes** — reset rápido; `__EFMigrationsHistory` ignorada.
- **Um container para a suíte** via `ICollectionFixture` (não `IClassFixture`).
- **Mocke só a fronteira do processo** (integrações externas, contexto de usuário);
  o UseCase e o EF Core rodam de verdade.
- **Resolva o UseCase do DI**, não instancie à mão — testa o wiring real.
- **Asserts sobre o `Result`** (`IsSuccess`/`Value`/`Error.Type`), coerente com
  o [result-pattern](result-pattern.md).
- **Stubs de Options in-memory** para não quebrar o `ValidateOnStart()` no CI.
- **Confirme versões/sintaxe** de xUnit e Testcontainers via Context7 / MS Learn.
