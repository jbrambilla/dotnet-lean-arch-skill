# Evaluation cases — dotnet-lean-arch

Cases to test skill triggering. Run each prompt in a fresh session with the skill
installed and check the expected behavior. Changed the `description`? Run them all again.

## MUST trigger the skill

### Case 1 — explicit API creation

- **Prompt**: "Create a .NET API from scratch for order management, with Postgres."
- **Expected**: skill loads; agent reads index and layers before coding; scaffold with
  4 layers, CPM, Result/Error in Domain, IApplicationDbContext, first IEndpoint.

### Case 2 — Clean Architecture term

- **Prompt**: "Set up a new C# backend following Clean Architecture."
- **Expected**: skill loads; applies the pragmatic variant of the blueprint (no MediatR,
  no generic repositories), not the classic/dogmatic version.

### Case 3 — new endpoint in an existing project

- **Prompt**: "Add an order cancellation endpoint to this API."
- **Expected**: skill loads; follows `references/how-to-add-endpoint.md`;
  IEndpoint with explicit authorization, calling a UseCase, no logic in the endpoint.

### Case 4 — new use case

- **Prompt**: "I need a UseCase for importing invoices, with validation."
- **Expected**: skill loads; follows `references/how-to-add-usecase.md`; UseCase,
  Validator, Request and Response in the same file; returns via Result.

### Case 5 — scaffolding with the stack named

- **Prompt**: "Scaffold a .NET 10 solution with EF Core and Aspire."
- **Expected**: skill loads; folder structure from the checklist (aspire/, src/, tests/),
  Directory.Build.props and Directory.Packages.props with CPM.

### Case 6 — layer organization question

- **Prompt**: "How should I organize the Domain, Application, Infra and Api layers of this service?"
- **Expected**: skill loads; answer based on the blueprint's dependency flow
  (Domain with no references; Api references Application + Infra), citing the references.

### Case 7 — cross-language triggering (pt-BR)

- **Prompt**: "Cria uma API em .NET do zero para gestao de pedidos, com Postgres."
- **Expected**: same as case 1 — the skill must trigger for prompts in Portuguese
  even though the `description` is in English.

### Case 8 — cross-language triggering (pt-BR)

- **Prompt**: "Preciso de um UseCase de importacao de notas fiscais com validacao."
- **Expected**: same as case 4 — cross-language triggering for a use-case request.

## Must NOT trigger the skill

### Case 9 — .NET, but not a backend/API

- **Prompt**: "Create a .NET console app that converts CSV to JSON."
- **Expected**: skill does NOT load; agent solves it directly, no layers, no scaffold.

### Case 10 — API, but the stack is not .NET

- **Prompt**: "Create a REST API in Node with Express and Prisma."
- **Expected**: skill does NOT load; plain Node/Express solution.

### Case 11 — conceptual question, nothing being built

- **Prompt**: "What is Clean Architecture and what are its pros and cons?"
- **Expected**: skill does NOT load; generic theoretical answer, without imposing the blueprint.

### Case 12 — maintenance on an existing API, no new endpoint/usecase

- **Prompt**: "Fix the null reference in this API's UsersController."
- **Expected**: skill does NOT load; targeted bugfix respecting the existing code.
