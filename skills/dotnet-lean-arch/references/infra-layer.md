---
tags: [architecture, dotnet, layer, infra, efcore, persistence]
aliases: [Infra, Infrastructure, Infrastructure Layer]
---

# 🟧 Infra Layer

> Technical details: EF Core, persistence, external integrations. Implements the
> abstractions defined in [Application](application-layer.md) and depends on
> [Domain](domain-layer.md).

See also: [index](index.md) · [application-layer](application-layer.md)

## Patterns and practices applied here

- [external-service-integration](external-service-integration.md) — external API gateways (Refit + ACL + resilience) live in `ExternalServices/`.
- [logging-observability](logging-observability.md) — the ServiceDefaults (Serilog + OpenTelemetry) and `HttpClient` resilience are composed in this layer.
- [typed-configuration](typed-configuration.md) — infrastructure `Options` (connection, external providers) validated at boot.
- [background-processing](background-processing.md) — the Hangfire runtime/storage and the `IBackgroundJobService` implementation live here.

## `ApplicationDbContext`

Implements the `IApplicationDbContext` abstraction from Application. Two
key responsibilities in the `SaveChangesAsync` override: applying the
configurations per assembly and filling in `Entity` timestamps automatically.

```csharp
using Microsoft.EntityFrameworkCore;
using Blueprint.Application.Abstractions;
using Blueprint.Domain;
using Blueprint.Domain.Shared;

namespace Blueprint.Infra.Persistence;

public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
    : DbContext(options), IApplicationDbContext
{
    public DbSet<Widget> Widgets { get; set; } = null!;
    public DbSet<Bar> Bars { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Applies every IEntityTypeConfiguration in this assembly.
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ApplicationDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }

    // Fills in CreatedAt / UpdatedAt automatically.
    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        var entries = ChangeTracker.Entries()
            .Where(e => e.Entity is Entity &&
                        (e.State == EntityState.Added || e.State == EntityState.Modified));

        foreach (var entry in entries)
        {
            ((Entity)entry.Entity).UpdatedAt = DateTime.UtcNow;
            if (entry.State == EntityState.Added)
                ((Entity)entry.Entity).CreatedAt = DateTime.UtcNow;
        }

        return base.SaveChangesAsync(cancellationToken);
    }
}
```

> The `internal` setter on `CreatedAt`/`UpdatedAt` (see [domain-layer](domain-layer.md)) allows
> only the Infra layer to write them — the domain does not manipulate them.
> Access comes from `<InternalsVisibleTo Include="<Sln>.Infra" />` declared in
> `Domain.csproj` as an MSBuild item — never a `Properties/AssemblyInfo.cs`.

## Entity configurations

One `IEntityTypeConfiguration<T>` class per entity, in `Persistence/Configurations/`.
All are applied automatically via `ApplyConfigurationsFromAssembly`.

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Blueprint.Domain;
using Blueprint.Domain.ValueObjects;

namespace Blueprint.Infra.Persistence.Configurations;

public sealed class WidgetConfiguration : IEntityTypeConfiguration<Widget>
{
    public void Configure(EntityTypeBuilder<Widget> builder)
    {
        builder.HasKey(w => w.Id);

        builder.Property(w => w.Name)
            .IsRequired()
            .HasMaxLength(120);

        builder.Property(w => w.Quantity)
            .IsRequired();

        // Value object persisted as a string conversion (1 column).
        builder.Property(w => w.Contact)
            .HasConversion(
                vo => vo.Value,
                value => Email.Create(value))
            .IsRequired()
            .HasMaxLength(254);

        builder.HasIndex(w => w.Name).IsUnique();
    }
}
```

### Reusable base (optional)

A `BaseEntityTypeConfiguration` can centralize what every entity shares
(key, timestamps):

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Blueprint.Domain.Shared;

namespace Blueprint.Infra.Persistence.Configurations;

public abstract class BaseEntityTypeConfiguration<T> : IEntityTypeConfiguration<T>
    where T : Entity
{
    public virtual void Configure(EntityTypeBuilder<T> builder)
    {
        builder.HasKey(e => e.Id);
        builder.Property(e => e.CreatedAt).IsRequired();
        builder.Property(e => e.UpdatedAt).IsRequired();
    }
}
```

## snake_case convention

Table and column names follow **snake_case** automatically (via
`EFCore.NamingConventions`), without annotating each property. Configured in the
DbContext registration.

## DI registration (`DependencyInjection.cs`)

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Blueprint.Application.Abstractions;

namespace Blueprint.Infra.Persistence;

public static class DependencyInjection
{
    public static IServiceCollection AddPersistence(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddDbContext<ApplicationDbContext>(options =>
            options
                .UseNpgsql(
                    configuration.GetConnectionString("app-db"),
                    npgsql => npgsql.EnableRetryOnFailure())
                .UseSnakeCaseNamingConvention()
                .EnableDetailedErrors());

        // Exposes the abstraction pointing to the concrete implementation.
        services.AddScoped<IApplicationDbContext>(
            sp => sp.GetRequiredService<ApplicationDbContext>());

        return services;
    }
}
```

And an `AddInfrastructure` aggregator that composes persistence + external services:

```csharp
public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddPersistence(configuration);
        // services.AddExternalServices(configuration);
        return services;
    }
}
```

## Migrations

The `DbContext` lives in Infra; the **Api** is the startup project. Commands:

```powershell
# Create
dotnet ef migrations add <Name> --project src/<Sln>.Infra --startup-project src/<Sln>.Api

# Apply manually
dotnet ef database update --project src/<Sln>.Infra --startup-project src/<Sln>.Api
```

In **Development**, it is common to apply migrations at startup (see [api-layer](api-layer.md)).

## External services

Integrations with third-party APIs live in `ExternalServices/<Provider>/`. The
abstraction (the `IXxxGateway` interface) lives in the [Application](application-layer.md); the
implementation (Refit client + ACL + options + handlers) lives here. The complete
pattern — Refit, Anti-Corruption Layer, resilience, logging with secret
redaction, and TokenManager — is in **[external-service-integration](external-service-integration.md)**.

## Principles

- **Infra implements, Application abstracts.** EF Core types do not leak outside.
- **One configuration per entity**, applied via assembly scanning.
- **Automatic timestamps** in `SaveChangesAsync` — do not write them by hand.
