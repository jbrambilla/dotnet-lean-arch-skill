# Casos de avaliacao — dotnet-lean-arch

Casos para testar o disparo da skill. Rode cada prompt em sessao nova com a skill
instalada e confira o comportamento esperado. Mudou a `description`? Rode todos de novo.

## Devem DISPARAR a skill

### Caso 1 — criacao explicita de API

- **Prompt**: "Cria uma API em .NET do zero para gestao de pedidos, com Postgres."
- **Esperado**: skill carrega; agente le index e camadas antes de codar; scaffold com
  4 camadas, CPM, Result/Error no Domain, IApplicationDbContext, primeiro IEndpoint.

### Caso 2 — termo Clean Architecture

- **Prompt**: "Monta um backend C# novo seguindo Clean Architecture."
- **Esperado**: skill carrega; aplica a variante pragmatica do blueprint (sem MediatR,
  sem repositorios genericos), nao a versao classica/dogmatica.

### Caso 3 — novo endpoint em projeto existente

- **Prompt**: "Adiciona um endpoint de cancelamento de pedido nessa API."
- **Esperado**: skill carrega; segue `references/como-adicionar-endpoint.md`;
  endpoint IEndpoint com autorizacao explicita, chamando UseCase, sem logica no endpoint.

### Caso 4 — novo usecase

- **Prompt**: "Preciso de um UseCase de importacao de notas fiscais com validacao."
- **Esperado**: skill carrega; segue `references/como-adicionar-usecase.md`; UseCase,
  Validator, Request e Response no mesmo arquivo; retorno via Result.

### Caso 5 — scaffolding com stack citada

- **Prompt**: "Faz o scaffolding de uma solucao .NET 10 com EF Core e Aspire."
- **Esperado**: skill carrega; estrutura de pastas do checklist (aspire/, src/, tests/),
  Directory.Build.props e Directory.Packages.props com CPM.

### Caso 6 — pergunta de organizacao de camadas

- **Prompt**: "Como devo organizar as camadas Domain, Application, Infra e Api deste servico?"
- **Esperado**: skill carrega; resposta baseada no fluxo de dependencias do blueprint
  (Domain sem referencias; Api referencia Application + Infra), citando as references.

## NAO devem disparar a skill

### Caso 7 — .NET, mas nao e backend/API

- **Prompt**: "Cria um console app em .NET que converte CSV para JSON."
- **Esperado**: skill NAO carrega; agente resolve direto, sem camadas nem scaffold.

### Caso 8 — API, mas stack nao e .NET

- **Prompt**: "Cria uma API REST em Node com Express e Prisma."
- **Esperado**: skill NAO carrega; solucao Node/Express comum.

### Caso 9 — pergunta conceitual, nada sendo construido

- **Prompt**: "O que e Clean Architecture e quais os pros e contras?"
- **Esperado**: skill NAO carrega; resposta teorica generica, sem impor o blueprint.

### Caso 10 — manutencao em API existente, sem novo endpoint/usecase

- **Prompt**: "Corrige o null reference no UsersController dessa API."
- **Esperado**: skill NAO carrega; bugfix pontual respeitando o codigo existente.
