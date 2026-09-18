# #436 — PR4 operational wiring and acceptance

Data: 2026-09-17. Entrega local no worktree `436-operations-integration`, sobre a base PR1 recebida. Wiring completo no escopo autorizado; aceitação Rails/HTTP/SQL **escrita, não executada**. Parent integra o classificador PR1 e faz rebase sobre reports/UI antes da suíte real em loopback. Este registro sucede as pendências de wiring de [436-operations.md](436-operations.md), preservado como histórico.

## Evidência e decisões

- Leitura: AGENTS, runbook/notas anteriores, controller/policy/config/Start/Request/Retry, jobs/run/migration, SuppressionRegistry, DeliveryClaim/Admission, Guardrail, modelos reais de reputação/provedor, auth da conta, contratos de retenção e specs recebidos. Pesquisa no overlay Enterprise não encontrou implementação própria destes componentes de manutenção.
- Rotas agora conectadas: POST create, GET show e POST retry sob a conta autenticada. Cron a cada minuto em housekeeping reconciliando somente até 100 outboxes/leases existentes. Não cria pedidos nem varre histórico sem run. Apply continua false por padrão, agora documentado em `.env.example`.
- Confirmação separada: apply exige `mode="apply"` e `confirm="apply"`, além de flag exato, motivo/chave/batch limitados. Preview rejeita confirm. Não converte preview. Type persistido `users.type=SuperAdmin` é autoridade, sem exigir instância STI Ruby SuperAdmin; promoção apenas em memória é rejeitada.
- Policy, Start, Retry e batches verificam associação atual à conta ativa e tipo persistido, sem cache de query. Retry revalida após obter o lock do run. Preview também para se perder acesso. Não transforma autenticação passada em permissão permanente.
- Retry antes era ilimitado: agora retry_count persistido, máximo 3 requisições por run, conferido sob lock. Migration ainda não aplicada no escopo recebeu a coluna default 0. Parent deve preparar schema atual no banco descartável; tabela criada por versão anterior não terá a coluna automaticamente. Não foi alterado db/schema.rb.
- Caminho inverso real: delete de Account obtém lock de Account e cascade tenta lock no run. Registry agora obtém Account. Antes, linha de backfill segurava run e esperava Account. Agora é Account → run → registry; Account aninhado do registry é da mesma transação. Não adquire locks de reputação/campanha/recipient nem altera a ordem Account → state → campaign → recipient. Claim/dispatch/finish/retry não obtêm Account depois de bloquear run. SQL de concorrência ainda precisa ser executado pelo parent.
- Mantidos batch máximo 500, teto inicial por ID, cursor e registry na mesma transação, 10 segundos entre linhas, lease/fencing, 3 tentativas de batch/enqueue e after_save_commit. Falhas/retry/status não retomam campanha ou enviam mensagem.
- Telemetria reaproveita Rails.logger estruturado e ActiveSupport::Notifications, com allowlist de progresso. Terminal failed também notifica. Nenhum coletor, IAM, alerta externo ou infra novo. Motivo/chave/token/payload/email não entram nesses payloads; isso não promete filtragem global de logs HTTP da aplicação.
- Dependência PR1 inspecionada somente leitura: `../436-delivery-integration/app/services/email_campaigns/complaint_classifier.rb`, contrato `EmailCampaigns::ComplaintClassifier.provider_prevented?(complaint)`. Evidence usa esse helper para Complaint/OnAccountSuppressionList e OnTenantSuppressionList → provider_suppression. Sem duplicar helper/fallback ou inventar API. Arquivo ainda deve ser integrado pelo parent antes de executar specs. Bounce global Suppressed permanece permanente/provider_suppression; NoEmail permanece permanent_failure genérico. Preview/apply compartilham Evidence.
- Registry mantém prioridade unsubscribe > complaint > manual > hard_bounce > provider_suppression > temporary_failure; nenhuma mudança nessa autoridade. Backfill preserva timestamps/proveniência, bridge legado e latches de conta/provedor. Referência de ator é lógica; nova FK Account → runs permanece cascade. Histórico de supressão mantém referências lógicas sem FKs restritivas.

## Aceitação acrescentada sem executar Rails

Specs HTTP reais usam as rotas e auth existentes: create/show/retry, sem autenticação, administrador comum, conta estrangeira mesmo com associação em ambas, associação revogada, tipo persistido rebaixado, confirmação ausente/malformada e retry de apply com flag off. Specs de serviço cobrem instância User com tipo persistido SuperAdmin, promoção falsa por becomes, conta suspensa, orçamento de retry e revogação durante abandono de lease.

Fluxo de aceitação HTTP: preview → jobs → apply → jobs → reimportação normalizada em outro domínio → gate real de claim. Expectativas proíbem construção do cliente SES e enqueue de DeliveryJob; verificam zero supressão no preview, bloqueio provider sem novo spam, campos de proveniência, notificações sem PII e fontes intactas. Outro fluxo usa modelos reais de reputação/provedor e compara atributos/histórico antes e depois de status/retry/apply, separando bloqueio de endereço por tenant do latch global do provedor.

Concorrência real escrita: claim exclusivo, Start idempotente, dois applies da mesma prova, jobs iniciais duplicados de preview, retry concorrente e preview simultâneo com apply. Cobertura recebida de rollback externo, continuidade after_commit, perdas de enqueue/callback/lease, cursor parcial, fencing, teto de 500, retenção/cascade e reimport foi mantida. Acrescentadas Complaint PREVENTED, preservação de unsubscribe e quarentena em shadow. Nenhum caso removido, nenhum skip. Não há alegação de que essas expectativas já passaram.

## Validação executada

1. RuboCop focado inicial: 27 arquivos; apontou estilo. Correção local de layout e exists?, com autocorreção limitada aos arquivos próprios e routes. Specs de aceitação mantêm um ciclo completo por exemplo, com exceção documentada somente para quantidade de expectativas; nenhuma expectativa desativada.
2. Último RuboCop sem autocorreção: **27 files inspected, no offenses detected**, exit 0.
3. Compilação Ruby sem executar classes/specs: **27 Ruby files compiled without execution; schedule.yml parsed**, exit 0. YAML foi apenas parseado com Psych. Nenhum boot Rails.
4. SHA256 conjunto Ruby ordenado, `path + NUL + content`, concatenado com NUL: `8529976221c4911b94ade73cdc1d4686b99b5929d033f4ba30935294a5f677f4`.

Comando RuboCop realmente executado (Ruby 3.4.4; cache em /private/tmp):

```sh
eval "$(rbenv init - zsh)"
RBENV_VERSION=3.4.4 RUBOCOP_CACHE_ROOT=/private/tmp/email436-operations-integration-rubocop bundle exec rubocop \
  app/services/email_campaigns/maintenance \
  app/models/email_protection_maintenance_run.rb \
  app/jobs/email_campaigns/protection_backfill_job.rb \
  app/jobs/email_campaigns/protection_backfill_reconcile_job.rb \
  app/controllers/api/v1/accounts/email_campaigns/maintenance_controller.rb \
  app/policies/email_protection_maintenance_policy.rb \
  db/migrate/20260916123000_create_email_protection_maintenance_runs.rb \
  spec/services/email_campaigns/maintenance \
  spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_backfill_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_acceptance_spec.rb \
  config/routes.rb --format simple
```

Sintaxe realmente executada com `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby -rpsych -rdigest` via STDIN: expandir os diretórios Ruby do comando acima, ordenar e chamar `RubyVM::InstructionSequence.compile_file` em cada arquivo; `Psych.parse_file('config/schedule.yml')`. Compilar não carrega Rails, resolve constantes de PR1 nem comprova rotas/SQL em runtime.

Nenhum RSpec, teste puro de aplicação, Rails, banco/migration, rede, SSH, AWS, SMTP, SendEmail, instalação, leitura de env real ou alteração em outro app/produção. Git foi usado somente para status/diff de leitura; nenhum write Git, commit, branch, PR, Project, merge ou deploy. `.husky/_/` já estava não rastreado e foi preservado.

## Manifesto completo para o parent — 33 arquivos

O pacote recebido tinha 27 arquivos (25 Ruby + 2 documentos). Acrescenta spec HTTP de aceitação, três arquivos de wiring, README e este audit. Arquivos recebidos são não rastreados nesta base: `git diff --stat` isolado mostra apenas os quatro arquivos rastreados de wiring/README, não o pacote inteiro. Não usar esse diff parcial como manifesto.

| Arquivo | Escopo nesta integração |
| --- | --- |
| app/controllers/api/v1/accounts/email_campaigns/maintenance_controller.rb | Recebido, revisado; agora roteado |
| app/policies/email_protection_maintenance_policy.rb | Tipo persistido e acesso atual |
| app/models/email_protection_maintenance_run.rb | Retry público limitado e telemetria terminal |
| app/jobs/email_campaigns/protection_backfill_job.rb | Recebido, revisado |
| app/jobs/email_campaigns/protection_backfill_reconcile_job.rb | Recebido, revisado; agora agendado |
| app/services/email_campaigns/maintenance/config.rb | Recebido, revisado; strings exatas/default false |
| app/services/email_campaigns/maintenance/request.rb | Confirmação explícita |
| app/services/email_campaigns/maintenance/start.rb | Autorização atual da conta |
| app/services/email_campaigns/maintenance/retry.rb | Autorização atual sob lock e cap persistido |
| app/services/email_campaigns/maintenance/dispatch.rb | Recebido, revisado; outbox after_commit |
| app/services/email_campaigns/maintenance/telemetry.rb | Notificações e logs estruturados |
| app/services/email_campaigns/maintenance/evidence.rb | ComplaintClassifier compartilhado de PR1 |
| app/services/email_campaigns/maintenance/historical_protection_backfill.rb | Account antes de run; ator atual em todos os batches |
| db/migrate/20260916123000_create_email_protection_maintenance_runs.rb | Retry count; cascade/lógica de retenção mantidos |
| spec/services/email_campaigns/maintenance/config_spec.rb | Recebido, mantido |
| spec/services/email_campaigns/maintenance/request_spec.rb | Confirmação e limites |
| spec/services/email_campaigns/maintenance/start_spec.rb | Tipo persistido/acesso atual/confirm |
| spec/services/email_campaigns/maintenance/retry_spec.rb | Cap, acesso e recuperação |
| spec/services/email_campaigns/maintenance/dispatch_spec.rb | Recebido, fixtures com acesso atual |
| spec/services/email_campaigns/maintenance/historical_protection_backfill_spec.rb | PREVENTED, precedência e quarentena |
| spec/services/email_campaigns/maintenance/recovery_spec.rb | Permissão revogada em retomada; confirm |
| spec/services/email_campaigns/maintenance/concurrency_spec.rb | Preview/apply/jobs iniciais/retry concorrentes |
| spec/services/email_campaigns/maintenance/reimport_backfill_spec.rb | Regressões mantidas; confirm/acesso atual |
| spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb | Regressões mantidas; confirm/acesso atual |
| spec/requests/api/v1/accounts/email_campaigns/maintenance_backfill_spec.rb | Três rotas HTTP e negativas |
| spec/requests/api/v1/accounts/email_campaigns/maintenance_acceptance_spec.rb | Novo; fluxo completo e preservação de guards reais |
| config/routes.rb | Três rotas account-scoped |
| config/schedule.yml | Cron somente de outboxes/leases existentes |
| .env.example | Apply false por padrão |
| README.md | Link do runbook |
| docs/email-campaigns/operations.md | Contrato final, marcos/gates, rollback e comandos automatizados |
| docs/audit/436-operations.md | Histórico recebido, não reescrito |
| docs/audit/436-operations-integration.md | Este registro |

## Handoff e limites restantes

- Parent traz PR1/ComplaintClassifier e rebaseia sobre reports/UI; confere consumo comum de PREVENTED e permanente global em reports. Não executar suíte com stub substituindo o helper ausente para alegar conclusão.
- Parent prepara schema/migrations completos, inclusive retry_count, e executa os [comandos de aceitação local](../email-campaigns/operations.md#aceitação-automatizada-local--execução-pelo-parent) no harness SQL real em loopback. Sintaxe/lint não comprovam after_commit, concorrência, autenticação nem cardinalidade dos modelos em runtime.
- Parent mantém aggregate docs/CI remoto, PR/Project e review. Merge/deploy/configuração/apply precisam dos gates e aprovação explícita; nada disso foi efetuado nesta rodada.
- Runbook distingue shadow/warning/enforce de higiene e reputação, monitor/DNS/backfill independentes, observação das duas stacks após cada merge blue-green, proteção opt-out/quarentena retida e ausência de liberação automática de latch histórico.

## Validação funcional pelo integrador

Migração123000 aplicada somente em banco sintético loopback; schema regenerado contém `retry_count`. A suíte própria passou em **108 exemplos, zero falhas**. A suíte cumulativa de higiene/reputação/operações e baseline passou em **596 exemplos, zero falhas, um pending preexistente de Account**. Os eventos append-only retidos por testes concorrentes de outra conta foram preservados; as expectativas dos testes de manutenção passaram a usar o escopo da conta, sem apagar auditorias nem alterar código de produto para ocultar dados.

RuboCop cumulativo: **147 arquivos sem infrações**. Revisão independente estática: PASS, sem achados concretos nos controles de autorização, preview/apply, isolamento, locking, idempotência, fencing, recuperação ou redação. Os nove problemas de setup do primeiro runtime foram corrigidos com identidade remetente reutilizada, autenticação HTTP real e verificações pós-commit isoladas dos jobs de criação de usuário. Nenhum teste novo foi ignorado.

Evidências locais: `tmp/email436/operations-second.json`, `operations-cumulative-final.json`, `operations-cumulative-lint.log` e `operations-independent-review.md`. A integração com as PRs de relatórios/UI e CI remoto será validada novamente no SHA final. Nenhum backfill de produção, chamada real de envio, alteração de flags, merge ou deploy.
