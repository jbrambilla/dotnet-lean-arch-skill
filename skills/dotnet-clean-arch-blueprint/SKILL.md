---
name: dotnet-clean-arch-blueprint
description: >-
  Blueprint arquitetural agnostico para construir backends .NET (Clean Architecture
  em 4 camadas, .NET 10, sem MediatR, Result pattern, validacao em dois niveis,
  configuracao tipada, EF Core, Aspire, Serilog/OpenTelemetry). Use esta skill
  SEMPRE que for criar um novo backend/API em .NET do zero, fazer scaffolding de
  uma solucao .NET, montar camadas Domain/Application/Infra/Api, ou quando o usuario
  mencionar Clean Architecture, UseCase, IEndpoint, Result pattern, IApplicationDbContext
  em contexto .NET/C#. Tambem ao adicionar endpoint ou usecase novo seguindo este padrao.
---

> **Esta skill e um blueprint portavel.** O corpo abaixo diz *como atuar*; os
> arquivos em [`references/`](references/) sao o detalhe de cada camada, padrao,
> pratica, referencia e guia. Os links resolvem por caminho relativo.


# 🤖 Blueprint .NET — Ponto de entrada

> **Você (agente de IA) está começando aqui.** Este é o blueprint arquitetural
> para backends .NET. Este documento diz **como atuar**; o
> [index](references/index.md) é o **mapa** de todo o conteúdo. Leia este documento
> inteiro, depois use o [index](references/index.md) para navegar até o que precisar.

## Como esta skill está organizada

```
dotnet-clean-arch-blueprint/
├── SKILL.md         ← você está aqui (como atuar)
└── references/
    ├── index.md                 ← mapa de navegação (filosofia + fluxo de dependências)
    ├── camada-{domain,application,infra,api}.md   ← as 4 camadas
    ├── result-pattern.md, validacao-dois-niveis.md, configuracao-tipada.md  ← padrões
    ├── logging-observabilidade.md, estrategia-de-testes.md,
    │   integracao-servico-externo.md, autenticacao-e-seguranca.md,
    │   processamento-em-segundo-plano.md          ← práticas transversais
    ├── stack-e-dependencias.md, convencoes-e-nomenclatura.md  ← referência
    └── como-adicionar-{endpoint,usecase}.md       ← guias acionáveis
```

> Todos os arquivos de referência ficam **flat** em `references/`; os links entre
> eles são caminhos relativos (ex.: `[camada-domain](references/camada-domain.md)`).

## ⚠️ Leia antes de codar

1. Leia o [index](references/index.md) (filosofia + fluxo de dependências).
2. Leia as quatro camadas na ordem: [camada-domain](references/camada-domain.md) → [camada-application](references/camada-application.md) →
   [camada-infra](references/camada-infra.md) → [camada-api](references/camada-api.md).
3. Leia [stack-e-dependencias](references/stack-e-dependencias.md) **antes de fixar qualquer package** — use sempre
   as últimas versões e confirme a sintaxe atual via Context7 / Microsoft Learn.
4. Tenha [convencoes-e-nomenclatura](references/convencoes-e-nomenclatura.md) à mão como referência rápida.
5. Consulte as práticas conforme a tarefa exigir: [logging-observabilidade](references/logging-observabilidade.md),
   [estrategia-de-testes](references/estrategia-de-testes.md), [integracao-servico-externo](references/integracao-servico-externo.md).
6. Só então comece a escrever código. Resista a "pular para o controller".

## Ordem recomendada de implementação

A ordem segue o sentido das dependências — **de dentro para fora**:

### 1. Domain (núcleo, sem dependências)
- Crie os tipos compartilhados primeiro: `Entity`, `AggregateRoot`,
  `DomainException`, `Result`/`Result<T>`, `Error`/`ErrorType`.
- Modele as entidades e value objects do domínio. Ver [camada-domain](references/camada-domain.md).

### 2. Application (orquestração)
- Defina a abstração `IApplicationDbContext`.
- Crie o primeiro UseCase (UseCase + Validator + Request + Response no mesmo
  arquivo). Ver [camada-application](references/camada-application.md) e [como-adicionar-usecase](references/como-adicionar-usecase.md).
- Defina as classes de `Options` tipadas. Ver [configuracao-tipada](references/configuracao-tipada.md).
- Se houver integração externa, defina a abstração `IXxxGateway` aqui. Ver
  [integracao-servico-externo](references/integracao-servico-externo.md).

### 3. Infra (detalhes)
- Implemente o `ApplicationDbContext : IApplicationDbContext`.
- Configure entidades (`IEntityTypeConfiguration`), snake_case, migrations.
  Ver [camada-infra](references/camada-infra.md).
- Implemente os gateways de serviços externos (Refit + ACL + resiliência). Ver
  [integracao-servico-externo](references/integracao-servico-externo.md).

### 4. Api (entrada + composição da raiz)
- Implemente o primeiro `IEndpoint`. Ver [camada-api](references/camada-api.md) e [como-adicionar-endpoint](references/como-adicionar-endpoint.md).
- Configure `GlobalExceptionHandler` e `ResultExtensions`.
- Monte o `Program.cs`: Serilog + try/catch/finally, registre serviços de todas as
  camadas, mapeie endpoints. Ver [logging-observabilidade](references/logging-observabilidade.md).
- **Mantenha o API atualizado** ao adicionar/alterar endpoints (índice + exemplos).
- Declare a **autorização explicitamente** em cada endpoint
  (`.RequireAuthorization()` / `.AllowAnonymous()`). Ver [autenticacao-e-seguranca](references/autenticacao-e-seguranca.md).

### 5. Testes (em paralelo, desde o início)
- Unitários de domínio (rápidos) e integração de UseCase com TestContainers.
  Ver [estrategia-de-testes](references/estrategia-de-testes.md).

> Precisa de trabalho assíncrono fora do request? Use um **Job** (≠ UseCase) com
> Hangfire isolado na Infra. Ver [processamento-em-segundo-plano](references/processamento-em-segundo-plano.md).

## Checklist de scaffolding

### Estrutura de pastas do projeto
```
.
├── Directory.Build.props          # defaults globais de todos os projetos
├── Directory.Packages.props       # versões centralizadas de pacotes (CPM)
├── nuget.config                   # fontes de pacote
├── <Solucao>.slnx                 # solution file
├── aspire/
│   ├── <Solucao>.AppHost/         # orquestração (opcional)
│   └── <Solucao>.ServiceDefaults/ # OTel, health checks, service discovery, Serilog
├── src/
│   ├── <Solucao>.Domain/
│   ├── <Solucao>.Application/
│   ├── <Solucao>.Infra/
│   └── <Solucao>.Api/
└── tests/
    ├── <Solucao>.UnitTests/
    └── integration/<Solucao>.IntegrationTests/
```

### `Directory.Build.props` (raiz)
```xml
<Project>
    <PropertyGroup>
        <TargetFramework>net10.0</TargetFramework>
        <ImplicitUsings>enable</ImplicitUsings>
        <Nullable>enable</Nullable>
    </PropertyGroup>
</Project>
```

> Versões e curadoria de packages: ver [stack-e-dependencias](references/stack-e-dependencias.md).

### `Directory.Packages.props` (Central Package Management)
```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <!-- Defina a VERSÃO aqui; nos .csproj referencie SEM versão -->
    <PackageVersion Include="FluentValidation.DependencyInjectionExtensions" Version="..." />
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="..." />
    <!-- ... -->
  </ItemGroup>
</Project>
```
> Nos `.csproj`: `<PackageReference Include="..." />` (sem `Version`).

### Referências entre projetos
- `Api.csproj` → referencia `Application` + `Infra` (+ `ServiceDefaults`).
- `Infra.csproj` → referencia `Application` (e transitivamente `Domain`).
- `Application.csproj` → referencia `Domain`.
- `Domain.csproj` → **nenhuma** referência de projeto.

### ServiceDefaults (se usar orquestração)
Centraliza OpenTelemetry, health checks (`/health`, `/alive`), service discovery,
resiliência de `HttpClient` e a configuração do Serilog. Exposto via
`AddServiceDefaults()` / `MapDefaultEndpoints()` chamados no `Program.cs`.
Ver [logging-observabilidade](references/logging-observabilidade.md).

## Definition of done do scaffold

- [ ] Solução compila com as 4 camadas e dependências corretas.
- [ ] CPM ativo; nenhum `.csproj` fixa versão de pacote.
- [ ] `Result`/`Error` e `Entity` base existem no Domain.
- [ ] `IApplicationDbContext` definido na Application e implementado na Infra.
- [ ] Pelo menos um `IEndpoint` mapeado e respondendo.
- [ ] `GlobalExceptionHandler` registrado; erros viram ProblemDetails.
- [ ] Serilog configurado via `appsettings.json`; `Program.cs` em try/catch/finally
      com bootstrap logger e file sink de fallback. Ver [logging-observabilidade](references/logging-observabilidade.md).
- [ ] `Program` acessível ao teste (`public partial class Program;`); ao menos um
      teste de integração de UseCase com TestContainers. Ver [estrategia-de-testes](references/estrategia-de-testes.md).
- [ ] Integrações externas (se houver) atrás de `IXxxGateway` com ACL e resiliência.
      Ver [integracao-servico-externo](references/integracao-servico-externo.md).
