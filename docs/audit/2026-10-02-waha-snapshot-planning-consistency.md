# WAHA — consistência do snapshot durante o planejamento

Data: 2026-10-02.
Issue: https://github.com/autonom-ia2/chat/issues/850.
PR de origem: https://github.com/autonom-ia2/chat/pull/842.
Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`.
Branch: `feat/waha-2026-9-2-chatwoot-sync`.
Base: `ff0f05293271c3d9c2d9fa25ef228188ace86b2d`.

## Escopo

Rodrigo autorizou o primeiro item dos novos achados da revisão independente #846/#848.
Handoff integralmente relido antes das alterações. Esta mudança fecha somente a incoerência do snapshot
do Chatwoot entre as leituras do planejamento. Preserva R1–R5/N1–N3 e os specs em quarentena.
Sem UI, Guia, refatoração ampla, merge, deploy, backfill real, produção, autenticação, QR ou pareamento.
O candidato #848 permanece uma fotografia anterior; esta correção não o atualiza automaticamente.

## Causa e correção

O planner lia o Chatwoot individual, depois a sessão e a lista completa de Apps. Conferia somente se o ID/tipo
do Chatwoot existia na lista. Uma mudança concorrente nesse intervalo deixava `snapshot.chatwoot` antigo e
`snapshot.apps` novo. A checagem N1 antes da escrita aceitava a lista nova, mas o payload ainda usava o App antigo.

`validate_chatwoot_snapshot!` substitui a checagem booleana de presença. Mantém a busca por ID e tipo
e o erro existente de App ausente; depois compara o Hash completo das duas respostas. Qualquer diferença
gera `SkipError` com motivo humanizado antes de construir o plano:

> O App Chatwoot mudou entre as leituras do planejamento. Nenhuma alteração foi aplicada.

O updater existente registra `SKIP`. Em APPLY, para na primeira caixa sem PUT, start, recuperação ou
gravação local. Em dry-run, registra o conflito sem produzir plano de atualização dessa caixa.
Não há merge de configurações, projeção que ignore campos desconhecidos ou retry.
Hash equality não depende da ordem das chaves. A checagem N1 de sessão/lista antes de executar um plano
coerente e a recuperação R1 após tentativa real de escrita permanecem intactas.

## Novos testes

Seis exemplos no updater:

- Configuração conhecida alterada depois de capturar o GET individual.
- Configuração desconhecida alterada nesse intervalo.
- `enabled` alterado nesse intervalo.
- Campo desconhecido do App adicionado nesse intervalo.
- Conflito detectado também no dry-run, sem plano/escrita.
- App ausente da lista continua bloqueado com o motivo anterior.

Os quatro cenários APPLY começam com somente Chatwoot. O mock captura o objeto individual antigo e altera
o estado remoto antes da próxima leitura da lista. Exercitam planner/updater reais e persistência no banco
local de teste. Comprovam estado concorrente preservado, zero PUT/start/recuperação, atributos locais
intactos, `updated=0`, `skipped=1`, `halted=true` e nenhuma leitura da segunda caixa.
Os exemplos existentes cobrem caminho normal, lista reordenada, preservação de Apps não relacionados,
identidade R2, recuperação R1 e escopo N3.

## Validação

Ruby 3.4.4 via rbenv; `RAILS_ENV=test POSTGRES_HOST=localhost POSTGRES_DATABASE=chatwoot_test`.
Clientes simulados e HTTP externo bloqueado pelo harness. Nenhuma operação de produção.

- Antes da correção, `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb:196`:
  **6 exemplos, 5 falhas**. Os quatro conflitos APPLY produziram `updated=1`, `total=2`, sobrescrita remota
  e gravação local; dry-run produziu plano incompatível. App ausente já era bloqueado.
- Focados: `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  **53 exemplos, zero falhas**, tanto na primeira versão funcional quanto na versão final do helper.
- Regressão exata do checkpoint do relógio, na versão final:
  `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  **308 exemplos, zero falhas, três pendentes preexistentes**.
- Pendentes intactos: WebhookListener:127 e Conversation:774/802; não contam como aceites aprovados.
- `bundle exec rubocop app/services/waha/existing_inbox_migration_planner.rb spec/services/waha/existing_inbox_updater_spec.rb`:
  **2 arquivos, zero infrações** na versão final. A primeira versão inline apontou complexidade/estilo;
  ajuste manual no helper existente, sem desabilitar regras, seguido de regressão e lint novos.
- `git diff --check`: aprovado. Guia não tocado; `pnpm guia:check` não aplicável.

Revisão independente somente leitura aprovou o fechamento deste P1 sem novos bloqueadores no delta,
condicionada às suítes; os resultados acima satisfazem essa condição. Confirmou R2, o fail-stop existente
e a recuperação R1 sem alterações. Sintaxe dos dois arquivos e diff check também aprovados pelo revisor.

Saídas lidas e diff revisado antes do commit. Hooks normais devem ser executados e o patch commitado
comparado ao revisado antes do push, sem `--no-verify`. Resultado Git e revisão independente serão
registrados na Issue/PR após conclusão.

## Limites e pendências

Este item não torna GET/PUT atômicos. Manter a exigência de impedir escritores paralelos de configuração
durante piloto e recuperação. Igualdade estrita é fail-closed; representações diferentes entre os endpoints
também bloquearão o plano e precisam ser avaliadas no dry-run, sem relaxar a comparação automaticamente.

Continuam pendentes: P1 da sessão `STOPPED` na confirmação final, P2 da duplicidade do resolver,
limites operacionais das métricas, revisão do lote na base final, evidência de runtime/rollback das duas
instalações, escolha da caixa do piloto e aceites reais/autorização de publicação.
Sem override Enterprise do planner/updater encontrado na busca em `app`, `enterprise` e `spec/enterprise`.
