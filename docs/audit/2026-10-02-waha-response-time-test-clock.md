# WAHA — estabilização da regressão de tempos de resposta

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/845.
PR draft: https://github.com/autonom-ia2/chat/pull/842.
Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`.
Branch: `feat/waha-2026-9-2-chatwoot-sync`.
Base: `ea402501abf3295edf2486abfa785b2e3925c2c1` (N3).

## Escopo autorizado

Após a entrega N3, Rodrigo autorizou continuar com a pendência da regressão.
Handoff e auditoria N3 relidos antes das alterações. A execução trata apenas
da fragilidade de relógio em testes; nenhum código de produto foi alterado.
R1–R5 e N1–N3 preservados. Sem produção, merge, deploy, backfill, logout,
pareamento, UI ou alterações nos três testes em quarentena.

## Causa e correção

O grupo `reply time calculation flows` constrói uma linha do tempo relativa:
5.hours.ago, 4.hours.ago, 3.hours.ago e 2.hours.ago. Entre esses cálculos,
há criação de modelos e execução real de jobs locais. Cada cálculo usa o
relógio do momento; a duração do processamento entra no intervalo entre
mensagens, embora o teste espere exatamente uma hora com tolerância de um segundo.

No estado N3, a regressão anterior teve 3.604/3.603 segundos para 3.600 +/- 1.
A falha de first_response também foi reproduzida na base N2; reply_time já
foi reproduzida na base N1, conforme as auditorias N2/N3.

Correção de cinco linhas em `spec/models/conversation_spec.rb`: around com
`freeze_time { example.run }` somente no grupo afetado, usando o helper
ActiveSupport já incluído por rails_helper. As seis simulações usam um único
instante de referência, e o relógio é restaurado ao sair do bloco, inclusive
em caso de erro. Assertions, tolerâncias, fixtures, execução dos jobs e
verificação da quantidade de eventos permanecem iguais. Sem sleeps/retries,
sem ampliação de tolerância e sem desabilitar exemplos.

## Validação

Ruby 3.4.4, inicializado por `eval "$(rbenv init -)"`, com `RBENV_VERSION=3.4.4`.
RSpec com `RAILS_ENV=test POSTGRES_HOST=localhost POSTGRES_DATABASE=chatwoot_test`.
HTTP real bloqueado por WebMock; apenas banco/filas locais e GitHub de governança.

- Antes da correção: `bundle exec rspec spec/models/conversation_spec.rb:1133`:
  seis exemplos, uma falha (first_response = 3.602 segundos).
- Após a correção, mesmo comando: seis exemplos, zero falhas.
- `bundle exec rubocop spec/models/conversation_spec.rb`: um arquivo, zero infrações.
- `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  302 exemplos, zero falhas, três pendentes preexistentes. Primeira execução
  completa após a correção, sem repetição para obter verde.
- Pendentes intactos: WebhookListener:127, Conversation:774 e Conversation:802.
- `git diff --check`: aprovado.
- Guia não tocado; `pnpm guia:check` não aplicável.

Saídas completas lidas antes de commitar; validações sem encadeamento com commit.
Hooks normais, comparação entre o diff revisado e o commit para detectar reescritas,
e push normal à mesma branch. Issue #845 no Project jarvis #2 para Review após entrega.

## Revisão e próximo passo

O ajuste depende apenas do relógio de teste. ReportingEventListener continua
calculando first_response por message.created_at - last_non_human_activity,
e reply_time por message.created_at - waiting_since. Nenhuma regra real foi mudada.
O bloqueio do cronômetro resolve uma causa reproduzida; não mascara alterações
de duração, perda de eventos ou duplicação, que continuam sendo verificadas.

O handoff original e as auditorias N1/N2/N3 continuam como registro histórico,
inclusive as execuções vermelhas anteriores. Os três pendentes em quarentena
permanecem fora da aprovação. A preparação local não valida WAHA real,
normalização pós-PUT, sessões, QR/reconnect ou os aceites E2E.

Parar após entrega desta pendência. Revisão do PR, plano de deploy/rollback e
autorização explícita antes de merge/deploy/piloto continuam necessários.
