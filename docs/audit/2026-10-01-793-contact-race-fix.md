# PR #793 — correção da corrida de criação de contato

## Autorização e escopo

Rodrigo autorizou a correção do defeito de backend reproduzido na revisão
independente. Trabalho na branch isolada `codex/793-audit-design`, a partir de
`1acd2b1809`, para atualizar a PR #793 / Issue #792. Sem merge em main, deploy,
migration, alteração de dados de produção ou chamada paga de IA.

## Correção

`Crm::Cards::ContactCreator` agora adquire a trava da conta com
`FOR NO KEY UPDATE` antes da trava do card. É a mesma trava usada por
`RelationshipRegistration`; assim os dois fluxos novos de cadastro no CRM
esperam a transação anterior terminar antes de validar e inserir outro contato.

A força da trava mantém compatibilidade com `FOR KEY SHARE` adquirido pela FK
da chave de idempotência. A ordem conta → card evita a inversão entre essas
operações. Não há preflight duplicado, retry, merge automático de pessoas ou
nova coerção de telefone. A validação nativa do contato continua retornando
422 quando o segundo pedido de cadastro no card encontra um telefone existente;
o registro composto continua retornando seu conflito 409.

## Evidência de regressão

Foi acrescentado um teste com conexões PostgreSQL e sessões HTTP independentes,
sem fixtures transacionais. Uma barreira pausa o vencedor depois da validação
real do contato e antes do INSERT. O concorrente usa outra chave de idempotência.
`pg_blocking_pids` verifica a espera no banco, sem substituir locks por mocks.

Antes da mudança, **os três exemplos falharam**: o segundo request respondeu 201
em vez de conflito. Após a mudança, os três passaram:

1. Criar contato em um card → criar contato em outro card: 201 / 422.
2. Criar contato no card → criar contato com nova oportunidade: 201 / 409.
3. Nova oportunidade com contato → criar contato em card existente: 201 / 422.

Cada exemplo confirma um único contato, um único card ligado à pessoa, ausência
de oportunidade parcial do perdedor, rollback da chave perdedora e replay da
chave vencedora sem nova pessoa. Um caso adicional confirma que o mesmo telefone
continua permitido em contas diferentes, sem vincular o contato de outra conta.

## Validação executada

- Antes da correção: `bundle exec rspec
  spec/requests/api/v1/accounts/crm/contact_creation_concurrency_spec.rb`:
  **3 exemplos, 3 falhas esperadas**, sem erro de setup/cleanup na execução final.
- Depois: concorrência, serviço de criação, APIs de criação/vínculo, registro
  composto e criação de oportunidades: **110 exemplos, zero falhas**.
- `bundle exec rubocop` nos três arquivos Ruby alterados: **3 arquivos, nenhuma
  infração**, sem autofix.
- Isolamento: PostgreSQL `review793_test`, Redis local, jobs de teste. Nenhum
  callback externo foi executado por worker. Os dados da prova são sintéticos.

Revisão independente do QA: **aprovado tecnicamente no escopo dos dois writers
CRM, sem bloqueador novo encontrado**. O QA executou o spec concorrente isolado
(3 exemplos, zero falhas), repetiu junto do serviço (13 exemplos, zero falhas) e
confirmou RuboCop sem infrações. Não encontrou ordem inversa CRM card → conta.
A cópia local do gate de AST, comparando o delta com `origin/main`, também passou;
isso não corrige o gate original que ainda usa um SHA histórico.

## Limites e liberação

A correção fecha a corrida comprovada entre os escritores novos do CRM. Não
introduz unicidade global no banco: os escritores legados de contatos/importação
continuam usando seus contratos atuais. Uma mudança global precisa de preflight
dos telefones legados e plano próprio; não foi inserida nesta correção local.

As telas do commit anterior não foram modificadas. Não foi repetida a suíte
frontend, pois esta mudança é exclusivamente de backend.

A aprovação de release ainda depende do CI/runtime específico de Relacionamentos
(o workflow continua desabilitado manualmente), do gate de regex cuja base
histórica está desatualizada e da autorização explícita para merge/deploy.
Os checks gerais de tradução, Guia/Central e campanha passaram no head anterior;
isso não substitui o runtime específico nem comprova o head deste ajuste.

Rollback: reverter somente o commit de correção de aplicação. Não há migration
nem transformação de dados; a reversão reabre a corrida e exige manter esse
fluxo protegido de uso concorrente enquanto a correção não estiver instalada.
