# Issue 757 — correções da revisão final de frontend

29/09/2026. Entrega local para revisão do supervisor; **não é aprovação de release**. Fontes lidas: `.codex/relationships/review-ui-final.md`, `.codex/relationships/review-backend-final.md` e implementação atual dos callers, stores, composables e componentes. Alterações pré-existentes preservadas.

## Correções

1. **Bloqueio e callers nativos/CRM.** `ContactManageView` envia somente `id` e `blocked`. O drawer CRM compara endereço/cargo com a base do formulário e só envia as chaves realmente alteradas; editar nome não reenvia atributos antigos. Inspecionados também ContactDetails, ContactsList/ContactsForm, ContactForm/EditContact, ContactInfo, CrmCardAutoFollowupStatus, itens legados de atributos e CompanyProfileCard. Os demais payloads ativos encontrados já são nativos ou parciais; não houve refatoração do CRM.
2. **Confirmação por chave nos stores reais.** Actions Vuex de contato e Pinia de empresa compartilham `confirmedValues` com FieldEditor. Respostas de update aplicam os campos enviados e mesclam apenas as chaves de atributos confirmadas sobre o registro vivo. Exclusão remove somente as chaves pedidas. Snapshot completo retornado não restaura os demais atributos/campos. Avatar e opt-out atualizam seus próprios campos; vínculo nativo de empresa mantém o objeto resolvido pelo servidor. Um GET show iniciado antes da confirmação preserva os atributos confirmados e as exclusões. Troca de usuário/conta e CLEAR_USER invalidam confirmações pendentes, inclusive ida e volta ao contexto anterior. Falha de uma gravação mais nova não invalida confirmação bem-sucedida anterior.
3. **Foco, falha transitória e autorização.** `useRelationships` preserva configuração, definições e `can_manage` já confirmados diante de erro transitório de leitura; marca `error/stale` e permite retry. Rascunho aberto permanece no modal, inclusive após falha de save. 401/403 de leitura ou escrita limpam a autorização e fecham o rascunho; logout/troca de usuário continuam isolando o cache. Gerações impedem que leitura anterior à gravação ou revogação restaure o estado. Não há escrita otimista nem relaxamento de autenticação: o servidor continua decidindo cada escrita.
4. **Volta das mídias.** O watcher imediato respeita `query.media` e `mediaEnabled`; observa conta e empresa. A aba também é restaurada quando os flags terminam de carregar e volta ao Histórico ao desligar mídia. A query com filtros é preservada; o CompanyMedia existente continua lendo esses filtros.
5. **Acessibilidade e compatibilidade.** Configuração e filtros de mídia têm IDs únicos e labels associados aos inputs reais. FieldEditor usa IDs por instância, nome acessível e foco no editor/retorno ao botão após salvar ou cancelar. Mantidos os dois botões nas fichas, criação com descrição, gates de privilégio e renderer original para flag desligado/modo legacy. Nenhum editor/padrão de regex novo.

## Arquivos alterados nesta rodada

Implementação (prefixo `app/javascript/dashboard/`):

- `components-next/Relationships/confirmedValues.js`
- `components-next/Relationships/FieldEditor.vue`
- `components-next/Relationships/FieldConfigurator.vue`
- `components-next/Relationships/CompanyMedia.vue`
- `composables/useRelationships.js`
- `store/modules/contacts/actions.js`
- `stores/companies.js`
- `routes/dashboard/contacts/pages/ContactManageView.vue`
- `routes/dashboard/companies/pages/CompanyDetailView.vue`
- `routes/dashboard/crm/components/CrmCardDrawer.vue`

Specs relacionados (mesmo prefixo):

- `components-next/Relationships/specs/mixedResponses.spec.js` (novo; Vuex, Pinia e FieldEditor reais, servidor parcial simulado e respostas controladas)
- `components-next/Relationships/specs/FieldConfigurator.spec.js`
- `components-next/Relationships/specs/accountIsolation.spec.js`
- `store/modules/specs/contacts/actions.spec.js`
- `stores/specs/companies.spec.js`
- `routes/dashboard/companies/pages/CompanyDetailView.spec.js`
- `routes/dashboard/crm/components/CrmCardDrawer.spec.js`

Este documento completa os arquivos escritos nesta rodada. Não foram escritos Ruby, Docker, `.codex`, Playwright, `api/relationships.js`, APIHelper/auth ou configurações de ambiente. Os quatro imports do cliente configurado `dashboard/api/relationships` e o save/restore de `window.axios` nos specs do supervisor foram preservados. Nenhum raw axios novo no código de produto. Sem commit/push, operação remota, instalação, alteração/reinício dos servidores ou execução de E2E.

## Verificação e logs

Comando da rodada focada:

```sh
pnpm test app/javascript/dashboard/components-next/Relationships/specs app/javascript/dashboard/stores/specs/companies.spec.js app/javascript/dashboard/store/modules/specs/contacts/actions.spec.js app/javascript/dashboard/routes/dashboard/companies/pages/CompanyDetailView.spec.js app/javascript/dashboard/routes/dashboard/crm/components/CrmCardDrawer.spec.js --minWorkers=1 --maxWorkers=2
```

- **122 testes / 13 arquivos passaram**: `/private/tmp/relationships-ui-fix-final-tests.log`.
- Depois foi acrescentado o caso de flags carregados assincronamente na volta da mídia. Revalidação do único componente alterado: **4 testes passaram**, incluindo o caso novo. Log: `/private/tmp/relationships-ui-fix-media-return.log`. Total de casos distintos cobertos: 123; não houve suíte pesada/full.
- **19 casos de integração de frontend** com stores reais: ordens legado→novo e novo→legado com respostas invertidas, exclusões, mesma chave, GET atrasado, logout/conta, falha mais nova, avatar e vínculo nativo. Log individual: `/private/tmp/relationships-ui-fix-native.log`.
- ESLint nos 17 arquivos de implementação/specs: **zero erros, 276 warnings**, principalmente i18n, mais avisos de template. Log: `/private/tmp/relationships-ui-fix-final-lint.log`. Revalidação de CompanyDetailView após o caso de flags: zero erros, 21 warnings (`/private/tmp/relationships-ui-fix-media-lint.log`). Não foram suprimidas regras.
- `eval "$(rbenv init -)"` seguido de `pnpm relationships:check`: gate AST sem regex nova contra `8396d7255e097ba79507a22081701eb41ddb6ce5`; log `/private/tmp/relationships-ui-fix-final-ast.log`.
- `git diff --check`: sem erros; `/private/tmp/relationships-ui-fix-diff.log`.
- Inspeção de callers: `/private/tmp/relationships-ui-fix-callers.log`. Manifesto SHA-256 dos 17 arquivos de código/specs entregues: `/private/tmp/relationships-ui-fix-manifest.log`.

A primeira tentativa de Vitest com apenas `--maxWorkers=2` esbarrou no mínimo de threads configurado; foi corrigida para `--minWorkers=1 --maxWorkers=2`. Falhas intermediárias de fixtures/expectativas e dois erros de lint do spec novo foram corrigidos e revalidados. Os avisos de Browserslist e diretiva `on-clickaway` aparecem nos logs; não houve instalação/atualização para eliminá-los.

## Limites para o supervisor

A prova é unitária/integrada de frontend com HTTP simulado; não demonstra concorrência PostgreSQL, autorização real de escrita, comportamento de previews nem aceitação no navegador. A validação real do cliente configurado, rascunho/foco/modal, volta da mídia com filtros e ações nativas deve ser concluída pelo supervisor no ambiente isolado já rodando. Os achados Ruby/backend permanecem sob responsabilidade do backendagent. **Não declarar pronto para merge/deploy com base apenas nesta rodada.**
