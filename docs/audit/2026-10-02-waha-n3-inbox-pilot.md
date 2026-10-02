# WAHA 2026.9.2 — N3: filtro de piloto por Inbox

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/844.
PR em draft: https://github.com/autonom-ia2/chat/pull/842.
Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`.
Branch: `feat/waha-2026-9-2-chatwoot-sync`.
Base N3: `20be78d7dc184a92f346a3a91f09a6695f9e1a33` (N2).

## Autorização e escopo

Rodrigo autorizou seguir somente para N3. Handoff integralmente relido.
Sem merge, deploy, backfill real, sessão WAHA real, logout, pareamento ou UI.
R1–R5, N1 e N2 preservados; nenhuma alteração operacional em produção.

## Causa e correção

O rake/updater só oferecia filtro por conta, que poderia incluir várias caixas.
Agora `INBOX_ID` é opcional em ambos, em dry-run e APPLY. No updater, o filtro
usa a associação polimórfica Inbox/Channel::Api e o ID da Inbox, antes do planejamento
e das leituras remotas. `ACCOUNT_ID` combinado limita por interseção, sem fallback.
Sem `INBOX_ID`, o comportamento anterior continua, inclusive canais sem Inbox
chegarem à validação existente do planner.

O rake converte o novo parâmetro com Integer em base 10, exigindo valor positivo.
Valor fornecido vazio, inválido, zero ou negativo termina com código 1 antes de
construir o updater/cliente; não converte entrada malformada com to_i.
O filtro ACCOUNT_ID existente não foi alterado.
O log inicial passa a incluir `inbox_id`, usando ALL somente quando ausente.

Inbox inexistente, não-WAHA ou de conta incompatível produz total=0 e nenhum
acesso remoto. Zero itens não é comprovação de migração: o piloto precisa de
dry-run com total=1 e identidade/preflight válidos antes de autorizar APPLY.
O comando não acrescenta filtros CHANNEL_ID/SESSION ou retry.

Documentação inclui exemplos de piloto, combinação dos filtros e revalidação
com os mesmos IDs. O inventário antigo foi identificado como histórico e ligado
ao handoff posterior que registra WAHA_APPS_ON já habilitado/persistido;
nenhum estado atual de produção foi consultado ou presumido nesta execução.

## Novos testes

Dezoito exemplos adicionais:

- Updater: sete exemplos, incluindo quatro combinações dry-run/APPLY com/sem
  ACCOUNT_ID, outras caixas na mesma conta e em outra conta intactas e sem
  leituras remotas; conta incompatível, Inbox inexistente e provider não-WAHA.
- Rake: onze exemplos, incluindo defaults sem filtro, conta isolada, Inbox
  isolada, ambos os filtros em dry-run/APPLY, cinco valores inválidos que não
  constroem o updater e saída não-zero para SKIP em APPLY.

## Validação

Ruby 3.4.4, inicializado com `eval "$(rbenv init -)"` e `RBENV_VERSION=3.4.4`.
RSpec com `RAILS_ENV=test POSTGRES_HOST=localhost POSTGRES_DATABASE=chatwoot_test`.
HTTP externo bloqueado por WebMock; apenas testes locais e GitHub de governança.

- Primeira execução focada: 47 exemplos, uma falha na montagem do teste de
  Inbox inexistente. `destroy!` acionava cleanup WAHA do modelo; WebMock bloqueou
  a requisição antes de sair. Corrigido apenas o setup para usar um ID ausente.
- `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  47 exemplos, zero falhas após a correção.
- `bundle exec rubocop app/services/waha/existing_inbox_updater.rb lib/tasks/waha.rake spec/services/waha/existing_inbox_updater_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  quatro arquivos, zero infrações após ajuste manual de Style/FetchEnvVar.
- `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  primeira execução com 302 exemplos, duas falhas e três pendentes preexistentes.
  Falhas em Conversation:1182/1210, valores 3.604/3.603 segundos para expectativa
  de 3.600 +/- 1, após criação/processamento com relógio real. N2 já documentava
  a falha em 1210 também na base N1. Nenhum desses testes foi editado/desabilitado.
- Execução isolada dos dois exemplos na proposta: dois exemplos, uma falha
  (1182, 3.603 segundos); 1210 passou, confirmando variação entre execuções.
- Comparação na base N2 20be78d7dc: os únicos arquivos runtime alterados (updater
  e rake) foram temporariamente lidos daquele commit, sem reset/rebase. Os dois
  exemplos isolados tiveram uma falha em 1182 com 3.604 segundos; 1210 passou.
  Os arquivos N3 foram restaurados byte a byte, confirmação True. A falha em
  1210 já foi reproduzida na base N1 e registrada na auditoria N2. Esta execução
  ampliada não foi verde; não se contabilizam falhas como aprovação nem se repetiu
  a suíte até obter verde. Os 18 exemplos novos e todos os demais ativos passaram.
- Pendentes intactos: WebhookListener:127, Conversation:774 e Conversation:802.
- `git diff --check`: aprovado.
- Guia não foi tocado; `pnpm guia:check` não aplicável.

Nenhum teste/lint encadeado a commit. Saídas completas lidas antes do commit.

## Revisão curta e limites

Scope conferido com associação Channelable e sem override Enterprise para o
updater/rake. O planner/executor não mudou: identidade R2, filtros R3, snapshot
N1, recuperação R1 e fail-stop mantidos. Model/listener de N2 não foram alterados.

N1 não torna GET/PUT atômicos; o futuro piloto ainda exige impedir escritores
paralelos de configuração/Apps, inclusive durante recuperação. Verificação de
normalização legítima da WAHA no pós-PUT continua sendo aceite do piloto.
N2 preserva cálculo legado para eventos antigos sem snapshot/ciclos já em
andamento sem marcador; testar uma reabertura registrada pela nova versão.
Nenhum recálculo histórico ou novo escopo foi adicionado.

## Governança e próximo passo

Issue #844 no Project jarvis #2, prioridade P2. Entrega em commit isolado N3
com hooks normais e push à branch existente; PR #842 continua draft e itens
seguem para Review. Parar após entrega.

N1, N2 e N3 implementados no código da branch. Merge, deploy, piloto real,
E2E, confirmação de normalização da WAHA e rollout continuam pendentes de
autorização/execução. A fragilidade de relógio dos testes anteriores fica
explicitamente pendente de revisão; esta entrega não certifica regressão verde.
Preparação futura: revisar PR e plano de deploy/rollback,
escolher IDs da conta/caixa piloto, revisar dry-run de uma caixa e só então
autorizar APPLY unitário com observação dos oito aceites E2E do handoff.
Lote só depois desses aceites, sem iniciar ações operacionais nesta entrega.
