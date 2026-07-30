---
tags: [architecture, dotnet, tests, testcontainers, integration, xunit]
aliases: [Testing Strategy, Tests, TestContainers]
---

# 🧪 Testing Strategy

> Two levels: **domain unit tests** (fast, no infrastructure) and **UseCase
> integration tests** with a real database via **TestContainers**. The goal of
> the integration level is to be **faithful to the use case**: it runs the real
> UseCase, against a real PostgreSQL, mocking only what crosses the process
> boundary.

See also: [index](index.md) · [application-layer](application-layer.md) · [result-pattern](result-pattern.md) · [stack-and-dependencies](stack-and-dependencies.md) · [typed-configuration](typed-configuration.md)

## Pragmatic pyramid

| Level | What it covers | Infra | Speed |
| ----- | ----------- | ----- | ---------- |
| **Domain unit** | entity invariants, value objects, pure rules | none | ⚡ instant |
| **UseCase integration** | UseCase flow + persistence (EF Core + real database) | PostgreSQL container | 🐢 seconds |

> Do not try to cover everything at the integration level. Domain rules are
> cheap to test at the unit level; integration focuses on the end-to-end
> behavior of the UseCase.

## Packages

Confirm the **latest versions** via Context7 / Microsoft Learn (see
[stack-and-dependencies](stack-and-dependencies.md)) — the xUnit and Testcontainers APIs change between majors.

```
# Runner / SDK
Microsoft.NET.Test.Sdk
xunit
xunit.runner.visualstudio

# API test host
Microsoft.AspNetCore.Mvc.Testing

# Container + database reset
Testcontainers.PostgreSql
Respawn

# Asserts + mocks
Shouldly        # FluentAssertions became paid (v8+); Shouldly is the free replacement
NSubstitute
```

## Folder structure

`tests/` at the root, mirroring `src/`:

```
tests/
├── <Sln>.UnitTests/                      # domain, no container
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
        └── UseCases/<Resource>/
            └── <Action>Tests.cs
```

> The integration project references the **Api** project (`<Sln>.Api`) — that is
> the one `WebApplicationFactory<Program>` instantiates.

## Prerequisite: accessible `Program`

With top-level statements, the `Program` class is `internal` and
`WebApplicationFactory<Program>` cannot see it. Expose it at the end of `Program.cs`:

```csharp
// end of Program.cs
public partial class Program;   // required for the WebApplicationFactory
```

> Alternative: `<InternalsVisibleTo Include="<Sln>.IntegrationTests" />` in the Api `.csproj`.

---

## Level 1 — Domain unit

No container, no DI. Tests always-valid construction (see [domain-layer](domain-layer.md) and
[two-level-validation](two-level-validation.md)). Asserts with **Shouldly**.

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
    public void Create_ShouldThrowDomainException_WhenQuantityIsNegative()
    {
        var action = () => new Widget("contact@example.com", "Gear", -1);

        action.ShouldThrow<DomainException>();
    }

    [Theory]
    [InlineData("")]
    [InlineData("no-at-sign")]
    public void Email_Create_ShouldThrow_WhenFormatIsInvalid(string input)
    {
        Should.Throw<DomainException>(() => Email.Create(input));
    }

    [Fact]
    public void ChangeQuantity_ShouldUpdate_WhenValueIsValid()
    {
        var widget = new Widget("contact@example.com", "Gear", 1);

        widget.ChangeQuantity(10);

        widget.Quantity.ShouldBe(10);
    }
}
```

---

## Level 2 — Integration with TestContainers

### A. WebApplicationFactory

Starts **one** PostgreSQL container, applies the **real** migrations with
`MigrateAsync()` (zero maintenance, tests the migrations themselves) and prepares
**Respawn** to reset data between tests.

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

        // Accessing Services builds the host (already with the container's connection string).
        using (var scope = Services.CreateScope())
        {
            var ctx = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            await ctx.Database.MigrateAsync();   // applies the real migrations
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

    // Called before each test by IntegrationTestBase.
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
                // Connection points to the container.
                ["ConnectionStrings:app-db"] = _db.GetConnectionString(),

                // Options STUBS — see "Why in-memory config" below.
                ["Widget:BaseUrl"] = "https://stub.internal",
                ["Widget:Limit"] = "50",
                ["Widget:Parameters:0:Name"] = "foo",   // array syntax: Key:Index:Prop
                ["Widget:Parameters:0:Value"] = "bar",
            });
        });

        builder.ConfigureTestServices(services =>
        {
            // Repoints the DbContext to the container.
            services.RemoveAll<DbContextOptions<ApplicationDbContext>>();
            services.AddDbContext<ApplicationDbContext>(o => o.UseNpgsql(_db.GetConnectionString()));

            // Replaces dependencies that cross the process boundary with fakes.
            services.RemoveAll<IExternalNotifier>();
            services.AddSingleton(Substitute.For<IExternalNotifier>());
        });
    }
}
```

> ### Why in-memory config?
> The app uses [Options with `ValidateOnStart()`](typed-configuration.md). In CI, the
> `WebApplicationFactory` **boots the real application** — if any required key
> is missing, boot fails and the tests never run. Filling in in-memory **stubs**
> satisfies the validation **without loosening it**. It is the correct way to
> keep the fail-fast behavior and still test.

### B. Collection fixture — **one** container for the whole suite

⚠️ **Common pitfall:** `IClassFixture<Factory>` creates one factory (and one
container) **per test class**. To share **a single** container across all
classes, use `ICollectionFixture<Factory>` + `[CollectionDefinition]`.
The `[Collection]` attribute also serializes execution (avoids database conflicts).

```csharp
using Xunit;

namespace Blueprint.IntegrationTests.Abstractions;

[CollectionDefinition(IntegrationCollection.Name)]
public sealed class IntegrationCollection : ICollectionFixture<IntegrationTestWebAppFactory>
{
    public const string Name = "Integration";
}
```

### C. Test base

Creates a scope per test, exposes `DbContext`/`ServiceProvider`/`DataSeeder` and,
in `InitializeAsync` (runs **before each test**), **resets** the database and
**seeds** the initial state.

```csharp
using Microsoft.Extensions.DependencyInjection;
using Blueprint.Application.Abstractions;
using Blueprint.IntegrationTests.Data;
using Xunit;

namespace Blueprint.IntegrationTests.Abstractions;

[Collection(IntegrationCollection.Name)]   // all classes join the same collection
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

> **xUnit v3:** `IAsyncLifetime` now uses `ValueTask` (and inherits
> `IAsyncDisposable`). Adjust the signatures to your version — confirm via
> Context7 / Microsoft Learn.

### D. Seeder

Reproducible initial state, with getters for the tests' arrange phase.

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
            _widgets.Add(new Widget($"contact{i}@example.com", $"Widget {i}", i + 1));

        await dbContext.Widgets.AddRangeAsync(_widgets);
        await dbContext.SaveChangesAsync();
    }
}
```

### E. UseCase test

Resolves the UseCase **from the DI container** (does not instantiate it by hand) —
this tests the real wiring, with external deps already replaced by fakes in the
factory. Asserts on the [`Result<T>`](result-pattern.md).

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Blueprint.Application.Features.Widgets;
using Blueprint.Domain.Shared;
using Blueprint.IntegrationTests.Abstractions;
using Shouldly;
using Xunit;

namespace Blueprint.IntegrationTests.UseCases.Widgets;

public sealed class UpdateWidgetTests(IntegrationTestWebAppFactory factory)
    : IntegrationTestBase(factory)
{
    [Fact]
    public async Task Should_UpdateQuantity_WhenWidgetExists()
    {
        // Arrange
        var widget = DataSeeder.GetWidget();
        var useCase = ServiceProvider.GetRequiredService<UpdateWidgetUseCase>();
        var request = new UpdateWidgetRequest(widget.Id, 42);

        // Act
        var result = await useCase.Execute(request, CancellationToken.None);

        // Assert — Result contract
        result.IsSuccess.ShouldBeTrue();
        result.Value!.Quantity.ShouldBe(42);

        // Assert — persistence, in a NEW scope (avoids reading from the change tracker).
        using var verifyScope = factory.Services.CreateScope();
        var ctx = verifyScope.ServiceProvider.GetRequiredService<IApplicationDbContext>();
        var persisted = await ctx.Widgets.FirstOrDefaultAsync(w => w.Id == widget.Id);

        persisted.ShouldNotBeNull();
        persisted!.Quantity.ShouldBe(42);
    }

    [Fact]
    public async Task Should_ReturnNotFound_WhenWidgetDoesNotExist()
    {
        var useCase = ServiceProvider.GetRequiredService<UpdateWidgetUseCase>();

        var result = await useCase.Execute(
            new UpdateWidgetRequest(Guid.NewGuid(), 1), CancellationToken.None);

        result.IsFailure.ShouldBeTrue();
        result.Error!.Type.ShouldBe(ErrorType.NotFound);
    }
}
```

> **Change tracker tip:** the `DbContext` exposed by the base class and the
> resolved UseCase share the same scope/context. To assert that something
> **actually persisted**, read from a **new scope** (as above) — otherwise you
> may be reading the entity still tracked in memory.

> **Verifying mock interactions (NSubstitute):** `DidNotReceive()` /
> `Received()` must **chain the verified method** — on their own they are no-ops:
> ```csharp
> notifier.DidNotReceive().Send(Arg.Any<string>());   // ✅ verifies
> notifier.DidNotReceive();                           // ❌ asserts nothing
> ```

## Test naming convention

`Should_<ExpectedResult>_When<Condition>` — describing behavior, not
implementation.

```
Should_UpdateQuantity_WhenWidgetExists
Should_ReturnNotFound_WhenWidgetDoesNotExist
Should_ThrowDomainException_WhenQuantityIsNegative
```

Inside the body, separate **Arrange / Act / Assert** (with a comment or blank line).

## Principles

- **Real database via TestContainers** — fidelity > speed at the integration level.
- **`MigrateAsync()` for the schema** — tests the migrations themselves, zero maintenance.
- **Respawn between tests** — fast reset; `__EFMigrationsHistory` ignored.
- **One container for the suite** via `ICollectionFixture` (not `IClassFixture`).
- **Mock only the process boundary** (external integrations, user context);
  the UseCase and EF Core run for real.
- **Resolve the UseCase from DI**, do not instantiate by hand — tests the real wiring.
- **Asserts on the `Result`** (`IsSuccess`/`Value`/`Error.Type`), consistent with
  the [result-pattern](result-pattern.md).
- **In-memory Options stubs** so `ValidateOnStart()` does not break in CI.
- **Confirm versions/syntax** of xUnit and Testcontainers via Context7 / MS Learn.
