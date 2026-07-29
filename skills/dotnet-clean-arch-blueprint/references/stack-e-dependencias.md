---
tags: [arquitetura, dotnet, stack, dependencias, packages, mcp]
aliases: [Stack e Dependências, Packages, Pacotes Base]
---

# 📦 Stack e Dependências

> Curadoria dos packages-base e — **mais importante** — a diretriz de como
> escolher versões e sintaxe ao iniciar um projeto novo com este blueprint.

Ver também: [index](index.md) · [AGENTS](../SKILL.md) · [logging-observabilidade](logging-observabilidade.md) · [configuracao-tipada](configuracao-tipada.md)

## ⚠️ Diretriz central (leia antes de adicionar qualquer package)

Este blueprint é **agnóstico de versão**. Ao instanciar um projeto novo:

1. **Sempre use a última versão estável** do .NET, do C# e de cada package — nunca
   copie números de versão "fossilizados" daqui.
2. **Não confie apenas no conhecimento de treino** para APIs, assinaturas, padrões
   e nomes de pacote. Eles mudam. **Confirme nas fontes de verdade abaixo.**
3. **Aproveite sintaxe nova do C#** quando a versão atual oferecer algo melhor
   (ex.: coleções de coleção, `field` keyword, primary constructors, pattern
   matching novo, etc.) — desde que melhore clareza, não por novidade.

### Fontes de verdade (MCPs)

- **Context7** — documentação atualizada de bibliotecas/frameworks (EF Core,
  FluentValidation, Serilog, OpenTelemetry, Aspire...). Use **antes** de escrever
  configuração ou chamadas de API de qualquer package.
- **Microsoft Learn** — referência oficial de .NET, C# e ecossistema Microsoft
  (novidades de linguagem, APIs de `Microsoft.Extensions.*`, EF Core, ASP.NET
  Core). Use para confirmar a sintaxe/recurso mais recente.

> Regra prática: **antes de fixar um package no `Directory.Packages.props` ou usar
> uma API nova, faça uma checagem rápida no Context7 e/ou Microsoft Learn.** É
> barato e evita código desatualizado já no nascimento do projeto.

## Gestão de versões — CPM

As versões são centralizadas em `Directory.Packages.props` (Central Package
Management). Ver [AGENTS](../SKILL.md).

- No arquivo central: `<PackageVersion Include="..." Version="..." />`.
- Nos `.csproj`: `<PackageReference Include="..." />` (**sem** `Version`).

## Packages-base por categoria

Lista **referencial** do que costuma compor este stack — **sem versão** de
propósito (confirme a última na hora). Inclua só o que o projeto realmente usa.

### Persistência (EF Core + PostgreSQL)
- `Microsoft.EntityFrameworkCore` — ORM.
- `Microsoft.EntityFrameworkCore.Design` — tooling de migrations (assets privados).
- `Npgsql.EntityFrameworkCore.PostgreSQL` — provider PostgreSQL.
- `EFCore.NamingConventions` — convenção **snake_case** automática. Ver [camada-infra](camada-infra.md).

### Validação
- `FluentValidation.DependencyInjectionExtensions` — validators + registro por
  assembly. Ver [validacao-dois-niveis](validacao-dois-niveis.md).

### Configuração tipada / Options
- `Microsoft.Extensions.Options.ConfigurationExtensions` — bind de seções.
- `Microsoft.Extensions.Options.DataAnnotations` — `ValidateDataAnnotations()`.
  Ver [configuracao-tipada](configuracao-tipada.md).

### API / OpenAPI
- `Microsoft.AspNetCore.OpenApi` — geração de documento OpenAPI para Minimal API.
  Ver [camada-api](camada-api.md).

### Logging (Serilog)
- `Serilog.AspNetCore` — integração + `UseSerilogRequestLogging`.
- `Serilog.Sinks.OpenTelemetry` — exporta logs via OTLP.
- Enrichers conforme necessidade: `Serilog.Enrichers.Environment`,
  `Serilog.Enrichers.Process`, `Serilog.Enrichers.Thread`.
- (File sink, normalmente já incluso no `Serilog.AspNetCore`, para o **fallback**
  em disco.) Ver [logging-observabilidade](logging-observabilidade.md).

### Observabilidade (OpenTelemetry)
- `OpenTelemetry.Extensions.Hosting` — wiring no host.
- `OpenTelemetry.Exporter.OpenTelemetryProtocol` — exporter OTLP.
- `OpenTelemetry.Instrumentation.AspNetCore`, `.Http`, `.Runtime` — instrumentação.
- `Npgsql.OpenTelemetry` — instrumentação do provider PostgreSQL.

### Integração HTTP / serviços externos
- `Refit.HttpClientFactory` — clientes HTTP tipados (Refit) + `AddRefitClient`.
- (`System.IdentityModel.Tokens.Jwt` — só se houver TokenManager lendo expiração de JWT.)
  Ver [integracao-servico-externo](integracao-servico-externo.md).

### Processamento em segundo plano
- `Hangfire.AspNetCore` — servidor de jobs, dashboard e integração com DI.
- `Hangfire.PostgreSql` — storage PostgreSQL para os jobs.
- `OpenTelemetry.Instrumentation.Hangfire` — traces dos jobs (à época, **prerelease/beta**;
  confirme a versão atual). Vai nos ServiceDefaults. Ver [processamento-em-segundo-plano](processamento-em-segundo-plano.md).

### Resiliência / Service discovery
- `Microsoft.Extensions.Http.Resilience` — políticas padrão de `HttpClient`
  (`AddStandardResilienceHandler`, Polly v8). Ver [integracao-servico-externo](integracao-servico-externo.md).
- `Microsoft.Extensions.ServiceDiscovery` — resolução de endpoints.

### Orquestração local (opcional)
- `Aspire.Hosting.*` (ex.: `Aspire.Hosting.PostgreSQL`) — sobe dependências
  (banco, etc.) junto da app no AppHost. Ver [AGENTS](../SKILL.md).

### Testes
- `Microsoft.NET.Test.Sdk`, `xunit`, `xunit.runner.visualstudio` — runner/SDK.
- `Microsoft.AspNetCore.Mvc.Testing` — `WebApplicationFactory` para integração.
- `Testcontainers.PostgreSql` — banco real efêmero em container.
- `Respawn` — reset rápido de dados entre testes.
- `Shouldly` — asserts fluentes **gratuitos** (FluentAssertions virou pago em v8+).
- `NSubstitute` — mocks/fakes. Ver [estrategia-de-testes](estrategia-de-testes.md).

## Princípios

- **Versões sempre atuais**, confirmadas via Context7 / Microsoft Learn.
- **CPM**: versão no arquivo central; `.csproj` sem versão.
- **Minimalismo**: adicione um package só quando for usar de fato — sem dependência
  especulativa.
- **Sintaxe C# moderna** quando melhorar clareza/manutenibilidade.
