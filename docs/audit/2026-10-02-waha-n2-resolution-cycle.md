# WAHA 2026.9.2 — N2: resolução independente da ordem dos jobs

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/843.
PR em draft: https://github.com/autonom-ia2/chat/pull/842.
Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`.
Branch: `feat/waha-2026-9-2-chatwoot-sync`.
Base N2: `52a3df37b16ca3b765c0770bdab91c13b0dcd78c` (N1).

## Autorização e escopo

Rodrigo autorizou seguir somente para N2. Handoff integralmente relido.
Nenhuma alteração de produção, sessão WAHA real, backfill, merge, deploy ou UI.
N1 e R1–R5 mantidos. N3 permanece pendente.

## Causa e fontes examinadas

`conversation_opened` e `conversation_resolved` são enfileirados como EventDispatcherJob,
na fila critical, sem garantia de ordem de conclusão. A consulta R4 dependia de opened já persistido.
A reprodução nova executou as transições reais e desserializou os argumentos dos jobs;
resolução antes da abertura retornou 259.200 segundos em vez de 4.800.

`status_changed_at` é atribuído antes do save, mas é sobrescrito na próxima transição.
`updated_at`, `waiting_since` e estado atual recarregado via GlobalID não representam um ciclo anterior.
As mensagens de atividade também são assíncronas; não são fonte adequada para resolver a corrida.
Foram examinados Conversation, Dispatcher/AsyncDispatcher, EventDispatcherJob, ReportingEventListener,
ReportingEventHelper, RollupService e overlays Enterprise de Conversation e dispatchers/listeners.

## Correção

- Escopo compartilhado em `Conversation#waha_single_conversation?`: Channel::Api WAHA e trava de conversa única.
- Callback before_save somente em registros persistidos com mudança de status e dentro desse escopo.
- Campo interno no JSON existente: `waha_resolution_cycle_started_at`, sem migration/tabela/fila nova.
- Reabertura depois de resolved persiste o status_changed_at em ISO8601 com microssegundos.
- Resolved encerra o marcador com nil; nil distingue ciclo encerrado da ausência do marcador no primeiro ciclo.
- Se pending/snoozed ficar entre resolução e abertura, o primeiro open inicia o novo ciclo.
- Snooze/pending e novas aberturas de um ciclo ativo preservam o início original.
- Antes do enqueue de resolved, o payload captura o início anterior ao reset como um Time independente do GlobalID.
- O listener usa esse timestamp diretamente, sem consultar opened/resolved para escolher o início.
- Primeiro ciclo conserva created_at. Horário comercial, eventos de bot e rollups usam o mesmo início.

A resolução de um ciclo antigo continua correta após reload e outros ciclos.
Nenhuma métrica histórica é reescrita, e a métrica do próprio conversation_opened não foi alterada.
Eventos já enfileirados antes deste código, sem snapshot, e ciclos já ativos sem marcador conservam
a origem legada. A proteção completa começa nas reaberturas registradas por esta versão.
O piloto deve testar uma reabertura após instalação; não se propõe backfill histórico neste item.

## Cobertura

Os dois exemplos sintéticos de R4 foram substituídos por transições reais de status e
argumentos de EventDispatcherJob serializados/desserializados. Doze cenários no grupo WAHA
(dez exemplos a mais no arquivo):

- resolução antes de opened e antes da resolução anterior;
- ordem cronológica equivalente;
- preservação de outros atributos e encerramento do marcador;
- snooze/múltiplas aberturas, jobs de abertura atrasados em ordem inversa;
- ciclo posterior já concluído antes do job de resolução anterior;
- pending entre resolved e open;
- primeiro ciclo sem resolução anterior;
- horário comercial e rollups com o início capturado;
- duração de bot igual à resolução comum;
- job anterior sem snapshot;
- canal não-WAHA com trava;
- WAHA sem trava.

## Validação e resultados

Ruby 3.4.4, shell iniciado com `eval "$(rbenv init -)"` e `RBENV_VERSION=3.4.4`.
RSpec com `RAILS_ENV=test POSTGRES_HOST=localhost POSTGRES_DATABASE=chatwoot_test`.
HTTP externo bloqueado por WebMock; apenas banco/filas locais de testes e GitHub de governança.

- Reprodução anterior à correção: 40 exemplos, cinco falhas novas, incluindo 259.200 vs 4.800 segundos.
- `bundle exec rspec spec/listeners/reporting_event_listener_spec.rb`: versão final com 41 exemplos, zero falhas.
- `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb`: execução final com 284 exemplos, zero falhas, três pendentes preexistentes.
- Pendentes: WebhookListener em linha 127, Conversation em linhas 774 e 802; quarentenas existentes, intactas e não contadas como aprovação.
- A primeira regressão ampliada teve uma falha de relógio em `spec/models/conversation_spec.rb:1218`: 3.602 vs 3.600 +/- 1 segundo. Execução isolada na proposta retornou 3.606.
- Comparação no código anterior N1 (model/listener temporariamente lidos de 52a3df37b1, sem reset/rebase): o mesmo exemplo falhou com 3.603. Ambos os arquivos N2 foram restaurados byte a byte, confirmação True. O teste usa relógio real entre criação/processamento de mensagens; não foi alterado nem desabilitado.
- A repetição da regressão completa passou sem alteração de código/teste; não se oculta a intermitência comprovada na base.
- `bundle exec rubocop app/models/conversation.rb app/listeners/reporting_event_listener.rb spec/listeners/reporting_event_listener_spec.rb`: três arquivos, zero infrações.
- `git diff --check`: aprovado.
- Guia não tocado: `pnpm guia:check` não aplicável.

Saídas completas lidas; nenhuma validação encadeada ao commit. Ajustes de RuboCop foram manuais.
Revisão do diff: callback na mesma persistência do status, scope compartilhado, snapshot escalar
anterior ao enqueue, primeiro início preservado e recuperação N1 intacta. Não há override Enterprise
para os métodos modificados; callbacks de SLA continuam recebendo o fluxo existente.

## Governança e próximo passo

Issue #843 adicionada ao Project jarvis #2, prioridade P2, para Review após entrega.
Commit isolado N2, hooks normais e push à branch existente; PR #842 permanece draft.
Parar após N2. N3, revisão final, autorização de merge/deploy e piloto continuam pendentes.
