---
tags: [arquitetura, dotnet, camada, infra, efcore, persistencia]
aliases: [Infra, Infrastructure, Camada de Infraestrutura]
---

# 🟧 Camada Infra

> Detalhes técnicos: EF Core, persistência, integrações externas. Implementa as
> abstrações definidas na [Application](camada-application.md) e depende de
> [Domain](camada-domain.md).

Ver também: [index](index.md) · [camada-application](camada-application.md)

## Padrões e práticas aplicados aqui

- [integracao-servico-externo](integracao-servico-externo.md) — gateways de APIs externas (Refit + ACL + resiliência) vivem em `ExternalServices/`.
- [logging-observabilidade](logging-observabilidade.md) — os ServiceDefaults (Serilog + OpenTelemetry) e a resiliência de `HttpClient` são compostos nesta camada.
- [configuracao-tipada](configuracao-tipada.md) — `Options` de infraestrutura (conexão, provedores externos) validadas no boot.
- [processamento-em-segundo-plano](processamento-em-segundo-plano.md) — runtime/storage do Hangfire e a implementação de `IBackgroundJobService` ficam aqui.

## `ApplicationDbContext`

Implementa a abstração `IApplicationDbContext` da Application. Duas
responsabilidades-chave no override de `SaveChangesAsync`: aplicar as
configurações por assembly e preencher os timestamps de `Entity` automaticamente.

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
        // Aplica todas as IEntityTypeConfiguration deste assembly.
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ApplicationDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }

    // Preenche CriadoAs / AtualizadoAs automaticamente.
    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        var entries = ChangeTracker.Entries()
            .Where(e => e.Entity is Entity &&
                        (e.State == EntityState.Added || e.State == EntityState.Modified));

        foreach (var entry in entries)
        {
            ((Entity)entry.Entity).AtualizadoAs = DateTime.UtcNow;
            if (entry.State == EntityState.Added)
                ((Entity)entry.Entity).CriadoAs = DateTime.UtcNow;
        }

        return base.SaveChangesAsync(cancellationToken);
    }
}
```

> O setter `internal` de `CriadoAs`/`AtualizadoAs` (ver [camada-domain](camada-domain.md)) permite
> que só a Infra os escreva — o domínio não os manipula.

## Configurações de entidade

Uma classe `IEntityTypeConfiguration<T>` por entidade, em `Persistence/Configurations/`.
Todas são aplicadas automaticamente via `ApplyConfigurationsFromAssembly`.

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

        builder.Property(w => w.Nome)
            .IsRequired()
            .HasMaxLength(120);

        builder.Property(w => w.Quantidade)
            .IsRequired();

        // Value object persistido como conversão para string (1 coluna).
        builder.Property(w => w.Contato)
            .HasConversion(
                vo => vo.Valor,
                valor => Email.Criar(valor))
            .IsRequired()
            .HasMaxLength(254);

        builder.HasIndex(w => w.Nome).IsUnique();
    }
}
```

### Base reutilizável (opcional)

Uma `BaseEntityTypeConfiguration` pode centralizar o que toda entidade compartilha
(chave, timestamps):

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
        builder.Property(e => e.CriadoAs).IsRequired();
        builder.Property(e => e.AtualizadoAs).IsRequired();
    }
}
```

## Convenção snake_case

Os nomes de tabelas e colunas seguem **snake_case** automaticamente (via
`EFCore.NamingConventions`), sem anotar cada propriedade. Configurado no registro
do DbContext.

## Registro no DI (`DependencyInjection.cs`)

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

        // Expõe a abstração apontando para a implementação concreta.
        services.AddScoped<IApplicationDbContext>(
            sp => sp.GetRequiredService<ApplicationDbContext>());

        return services;
    }
}
```

E um agregador `AddInfrastructure` que compõe persistência + serviços externos:

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

O `DbContext` vive na Infra; a **Api** é o startup project. Comandos:

```powershell
# Criar
dotnet ef migrations add <Nome> --project src/<Sln>.Infra --startup-project src/<Sln>.Api

# Aplicar manualmente
dotnet ef database update --project src/<Sln>.Infra --startup-project src/<Sln>.Api
```

Em **Development**, é comum aplicar migrations no startup (ver [camada-api](camada-api.md)).

## Serviços externos

Integrações com APIs de terceiros vivem em `ExternalServices/<Provedor>/`. A
abstração (interface `IXxxGateway`) fica na [Application](camada-application.md); a
implementação (cliente Refit + ACL + options + handlers) fica aqui. O padrão
completo — Refit, Anti-Corruption Layer, resiliência, logging com redação de
segredos e TokenManager — está em **[integracao-servico-externo](integracao-servico-externo.md)**.

## Princípios

- **A Infra implementa, a Application abstrai.** Tipos de EF Core não vazam para fora.
- **Uma configuração por entidade**, aplicada por assembly scanning.
- **Timestamps automáticos** no `SaveChangesAsync` — não os escreva à mão.
