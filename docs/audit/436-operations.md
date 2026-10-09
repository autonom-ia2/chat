# #436 — revisão final de manutenção/backfill

Data: 2026-09-16. **Correção local; Rails/RSpec e operação real pendentes.** Escopo desta rodada: manutenção, testes próprios e estes dois documentos. Sem comandos Git, Rails/RSpec, banco, migration executada, AWS, SSH, SMTP, rede, instalação, credenciais ou leitura de arquivos env reais. Não houve backfill, merge ou deploy. A compilação de Ruby abaixo não carrega nem executa as classes/specs.

## Achados demonstrados no código e correções

1. **Origem errada do bloqueio:** Evidence promovia todo `classification=permanent` para hard_bounce e ignorava as prevenções desconhecidas. Agora dá precedência ao `reason_code` de provider_suppression/unsubscribe, como o writer SNS real. Global Suppressed mantém classificação permanente/origem provider_suppression; OnAccount/OnTenant/EmailValidationSuppressed bloqueiam duravelmente sem alegar tentativa. UnsubscribedRecipient bloqueia como unsubscribe. NoEmail mantém permanent_failure, sem alegação de caixa inexistente.
2. **Precedência legada errada:** provider_suppression não estava na lista de razões fortes e virava manual, acima de hard_bounce. Agora preserva a razão original. O registry continua único escritor de estado/auditoria/espelho; sua prioridade não é duplicada nem alterada. Novas provas não liberam hard, complaint ou unsubscribe.
3. **Publicação antes do commit externo:** continuação e Retry chamavam Dispatch diretamente após um lock, podendo publicar antes de um transaction externo fazer commit. Ambos agora usam um único `after_save_commit` no model, limitado a estado pending com prazo de dispatch vencido. Usa estado/prazo, não saved_changes: leitura do ActiveRecord instalado confirmou que reload limpa dirty tracking antes do commit externo. A reserva futura impede republicação recursiva. A primeira publicação também usa esse callback. Reconciliador recupera commit sem callback, mensagem perdida, falha de enqueue e lease expirado; não descobre contas. Nenhuma agenda foi ligada aqui.
4. **Metadado livre replicado:** operador_reason era copiado para auditoria de supressão. Removido; motivo privado continua apenas no run. Metadados são IDs e códigos produzidos localmente. Progresso/logs próprios não expõem endereço, payload, chave, token ou motivo.

Leitura real adicional: modelos de supressão, migration de higiene, leitor legado/novo, importador, DeliveryClaim, writer SNS, Reports::Metrics, guardrail, Presentation, auth/Pundit e referências Enterprise. Nenhum override Enterprise específico da manutenção foi encontrado. Nenhuma edição fora da propriedade autorizada.

## Contratos preservados e limites

- Preview é default; apply exige string exata `mode=apply`, motivo/chave/batch válidos, flag true e SuperAdmin persistido. Aprovação humana é etapa do runbook: API não certifica aprovação nem vincula automaticamente apply a preview. Preview vazio/failed não é apply bem-sucedido; dry_run nunca é convertido.
- HTTP exige acesso à conta da URL; serviços internos verificam SuperAdmin. Retry só do ator original ainda autorizado e run failed. Autor removido/rebaixado interrompe próximo batch apply. Erros exatos e escopos: [operations.md](../email-campaigns/operations.md).
- Chaves do SNS/opt-out preservadas; idempotência por conta/endereço no registry. Horizonte inicial, cursor por linha atomicamente com registry, lease/fencing e orçamento de tentativas continuam. Contagens representam provas, não endereços únicos nem reputação oficial.
- Não há unlock, reset de trigger/histórico, reenvio, retomada ou override. Trocar domínio remetente/reimportar na mesma conta não contorna bloqueio. Escopo é tenant; não se inventa bloqueio global entre clientes.
- Migration123000 mantém FK da conta com cascade e ator lógico, sem FK. Higiene já mantém eventos de auditoria com referências lógicas sem FK restritiva e estados com cascade. Não se alterou a retenção legada nem a exclusão autorizada existente. Rollback de código preserva todos os positivos/estados/histórico; não executar down.

## Manifesto exato do pacote e desta revisão

25 arquivos Ruby e 2 documentos (27 no pacote). `alterado` significa editado nesta revisão; `novo` foi acrescentado agora; `revisado` não recebeu edição nesta rodada. Schema, routes, schedule, env, infraestrutura e outros workstreams não pertencem a este manifesto.

| Arquivo | Rodada final |
| --- | --- |
| app/services/email_campaigns/maintenance/config.rb | revisado |
| app/services/email_campaigns/maintenance/request.rb | revisado |
| app/services/email_campaigns/maintenance/start.rb | revisado |
| app/services/email_campaigns/maintenance/evidence.rb | alterado |
| app/services/email_campaigns/maintenance/historical_protection_backfill.rb | alterado |
| app/services/email_campaigns/maintenance/dispatch.rb | revisado |
| app/services/email_campaigns/maintenance/retry.rb | alterado |
| app/services/email_campaigns/maintenance/telemetry.rb | revisado |
| app/models/email_protection_maintenance_run.rb | alterado |
| app/policies/email_protection_maintenance_policy.rb | revisado |
| app/controllers/api/v1/accounts/email_campaigns/maintenance_controller.rb | revisado |
| app/jobs/email_campaigns/protection_backfill_job.rb | revisado |
| app/jobs/email_campaigns/protection_backfill_reconcile_job.rb | revisado |
| db/migrate/20260916123000_create_email_protection_maintenance_runs.rb | revisado |
| spec/services/email_campaigns/maintenance/config_spec.rb | revisado |
| spec/services/email_campaigns/maintenance/request_spec.rb | alterado |
| spec/services/email_campaigns/maintenance/start_spec.rb | alterado |
| spec/services/email_campaigns/maintenance/historical_protection_backfill_spec.rb | alterado |
| spec/services/email_campaigns/maintenance/recovery_spec.rb | alterado |
| spec/services/email_campaigns/maintenance/dispatch_spec.rb | alterado |
| spec/services/email_campaigns/maintenance/concurrency_spec.rb | alterado |
| spec/services/email_campaigns/maintenance/reimport_backfill_spec.rb | alterado |
| spec/services/email_campaigns/maintenance/retry_spec.rb | novo |
| spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb | alterado |
| spec/requests/api/v1/accounts/email_campaigns/maintenance_backfill_spec.rb | revisado |
| docs/email-campaigns/operations.md | alterado |
| docs/audit/436-operations.md | alterado |

## Validação realmente executada nesta rodada

RuboCop, sem autocorreção: primeira passagem encontrou `Performance/TimesMap` no novo teste de concorrência; corrigido para `Array.new`. Passagem seguinte e última passagem após ampliar regressões: **25 files inspected, no offenses detected**, exit 0. Ruby 3.4.4, cache somente em /private/tmp.

```sh
eval "$(rbenv init - zsh)"
RBENV_VERSION=3.4.4 RUBOCOP_CACHE_ROOT=/private/tmp/email436-maintenance-rubocop bundle exec rubocop \
  app/services/email_campaigns/maintenance \
  app/models/email_protection_maintenance_run.rb \
  app/jobs/email_campaigns/protection_backfill_job.rb \
  app/jobs/email_campaigns/protection_backfill_reconcile_job.rb \
  app/controllers/api/v1/accounts/email_campaigns/maintenance_controller.rb \
  app/policies/email_protection_maintenance_policy.rb \
  db/migrate/20260916123000_create_email_protection_maintenance_runs.rb \
  spec/services/email_campaigns/maintenance \
  spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_backfill_spec.rb --format simple
```

Sintaxe: `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby` via STDIN; lista dos 25 arquivos Ruby acima, ordenada, com diretórios expandidos por `Dir[]`; `files.each { |file| RubyVM::InstructionSequence.compile_file(file) }`. Resultado **25 Ruby files compiled without execution**, exit 0. SHA256 de `files.map { |path| "#{path}\0#{File.binread(path)}" }.join("\0")`: `3e42dd386f1c14d04b3defa5def22e7eb4b90bb00a6adc050a32b965b92bcc6d`.

O registro anterior deste pacote documentava 24 arquivos lintados/compilados e 34 asserções puras em STDIN. Eram anteriores ao fechamento dos subtipos e à correção operacional atual; **não validam o código final**. Nenhum teste puro ou Rails foi executado nesta revisão (autorização restrita a sintaxe/RuboCop).

## Regressões escritas, execução pendente do parent

Matriz NoEmail/global/account/tenant/validation/unsubscribe, metadata allowlist, preservação de prioridade e legado provider, dedupe com writer real, reimportação normalizada por outro domínio em shadow, preview vazio/failed, rollback externo antes de continuação/retry, publicação após commit externo apesar do reload de Start/Retry, recuperação de retry depois de enqueue falho/commit sem callback, reconciliação de lease expirado, limpeza de conta sem FK de auditoria restritiva, limites/cursores e atores. Concorrência real: lease exclusivo, Start com mesma chave, dois runs aplicando a mesma prova legada pelo registry com apenas um evento.

Comandos canônicos para o parent, **não executados nesta rodada**. Os puros têm resultados históricos em [436-hygiene.md](436-hygiene.md); usam Minitest/stdlib, não Rails. Eles validam higiene, não durabilidade PostgreSQL da manutenção:

```sh
/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby spec/pure/email_campaigns/hygiene_test.rb
/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby spec/pure/email_campaigns/preflight_batch_test.rb
```

**Somente no harness isolado do parent**, com banco descartável exclusivo já preparado com migrations atuais, rotas conectadas, fila de teste e configuração sintética que não carregue env/credenciais reais. `RAILS_ENV=test` sozinho não garante isolamento. A suíte concorrente desativa fixtures transacionais e exige conexões reais; nunca usar banco compartilhado. Estes comandos são a receita de execução pendente, não evidência de testes passados:

```sh
eval "$(rbenv init - zsh)"
RAILS_ENV=test RBENV_VERSION=3.4.4 bundle exec rspec \
  spec/services/email_campaigns/maintenance \
  spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_backfill_spec.rb
```

Parent deve incluir a suíte final de higiene/registry/SNS/import/DeliveryClaim, reports e testes reais de B na execução completa isolada. Não há comando de migrate/backfill/apply autorizado aqui.

## Pendências explícitas / handoff

- Parent conecta as três rotas, env de exemplo default false e scheduler opt-in em housekeeping conforme [operations.md](../email-campaigns/operations.md); reconciliação é necessária para recuperação durável. Nenhum wiring feito aqui.
- **Achado fora do escopo:** `Reports::Metrics#load_bounces` conta todo reason_code provider_suppression em provider_prevented, inclusive Suppressed global. O parent deve separar prevenção sem tentativa de permanente prejudicial, preservando o numerador permanente global. Fonte das taxas locais é sent_at/eventos, com official_ses_ratio=false; não são taxas oficiais SES.
- Presentation já referencia contratos B, mas os modelos/serviços finais Reputation/Provider não estavam presentes nesta inspeção. A preservação de trigger_snapshot/histórico/breaker global deve ser comprovada com os modelos finais. IAM, monitor, métricas oficiais e alarmes precisam do contrato real de B, sem permissões/limiares inventados.
- Testes Rails/RSpec/migration isolada, smokes HTTP pós-wiring, review independente, PR/Project e aprovação continuam pendentes. Não se declara operação concluída em produção, PR pronto ou autorização de merge.
- Sequência por PR e rollback estão no runbook: **cada merge dispara deploy blue-green nas duas stacks**; aprovação antes de cada merge e observação/smoke autorizado antes do seguinte. Sem down destrutivo, sem limpar supressões, sem reset de reputação.
