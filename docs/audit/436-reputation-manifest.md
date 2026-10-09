# Manifesto de integração — reputação #436

Este manifesto lista o conjunto atual alterado/novo do PR neste worktree, incluindo arquivos anteriores à revisão corretiva. `db/schema.rb` já estava modificado pelo parent e foi excluído: reconstrução/regeneração ficam com o parent. Sem commit.

## Mudanças de contrato que o parent precisa integrar

- Novas rotas: `GET /api/v1/accounts/:account_id/email_campaigns/reputation/history` (SuperAdmin, somente auditoria desse tenant); `POST /api/v1/accounts/:account_id/email_campaigns/reputation/provider_release` (SuperAdmin, motivo e consulta global fresca).
- `GET /reputation` agora retorna apenas `{protection, state}` sanitizado. Histórico separado. Avaliações/overrides públicos não incluem `override` bruto, ator, motivo ou orçamento. `override_active` e `resume_allowed` são capacidades públicas; guardas usam códigos canônicos.
- `EmailCampaign#resume!` passa a transição de campanha como bloco de `Guardrail.resume!`; o bloco executa dentro da publicação protegida **depois da coleta**. Não recolocar Account.with_lock em volta da chamada.
- `EmailEvent`: `before_save` → `EvaluationQueue.invalidate(account_id)` dentro da transação; `after_save_commit` → `EvaluationQueue.request(account_id)`. Integração com SQL em lote deve reproduzir esses dois pontos. Não invalidar apenas depois do commit.
- `ReputationEvaluationJob.perform(account_id, lease_token = nil)` aceita token opcional; solicitações novas devem usar `EvaluationQueue.request`, não enfileirar diretamente por feedback.
- `ProviderRelease.new.call(actor:, reason:)`: nova consulta, liberação auditada; retorno `{code: 'provider_released'}`. Não supera emergência/SES desabilitado/monitor desligado.
- Novos defaults `.env.example`: `EMAIL_REPUTATION_PROVIDER_BOUNCE_RATIO=0.05` e `EMAIL_REPUTATION_PROVIDER_COMPLAINT_RATIO=0.001`, validados como positivos e no máximo esses defaults. Monitor segue off.
- Novas migrações finais: **20260916121000 / 20260916121100 / 20260916121200**. Removidos os arquivos antigos **120000 / 120100 / 120200**; mesmas classes. Estado adiciona gerações/lease e FK cascade; provider adiciona latch; auditoria admite provider_key e IDs lógicos sem FKs restritivas. Trigger permite novo snapshot apenas em nova pausa após liberação.
- Specs concorrentes (`concurrency_spec`, `campaign_delivery_lock_spec`, `provider_concurrency_spec`) precisam de conexões reais, sem transações compartilhadas de fixture. Restante segue wrapper isolado do parent. Não executar testes puros `*_test.rb` por require dentro de Rails: possuem stubs mínimos destinados a processo Ruby independente.

## Delta final de classificação (2026-09-16)

Integrar apenas os seguintes arquivos desta rodada, preservando os demais patches existentes:

- `app/services/email_campaigns/reputation/metrics.rb`
- `spec/services/email_campaigns/reputation/metrics_spec.rb`
- `spec/services/email_campaigns/reputation/feedback_spec.rb`
- `spec/services/email_campaigns/reputation/policy_test.rb`
- `docs/email-campaigns/reputation.md`
- `docs/audit/436-reputation.md`
- `docs/audit/436-reputation-manifest.md`

`Permanent/Suppressed` permanece permanente/nocivo, sem implicar mailbox-not-found. Prevenção contém apenas `OnAccountSuppressionList`, `OnTenantSuppressionList`, `EmailValidationSuppressed`, `UnsubscribedRecipient`. Mantidos coorte local, defaults 5%/mínimo cinco, histórico após liberação e monitor off/sem evidência de saúde. O log do parent `reputation-v2-rspec-second.log` confirma 84 exemplos sem falhas antes desse delta; nova execução integrada fica com o parent. Comandos e resultados desta rodada constam na seção de fechamento da auditoria.

## Arquivos

- `.env.example`
- `app/controllers/api/v1/accounts/email_campaigns/base_controller.rb`
- `app/controllers/api/v1/accounts/email_campaigns/campaigns_controller.rb`
- `app/controllers/api/v1/accounts/email_campaigns/reputations_controller.rb`
- `app/jobs/email_campaigns/delivery_job.rb`
- `app/jobs/email_campaigns/guardrail_sweep_job.rb`
- `app/jobs/email_campaigns/provider_monitor_job.rb`
- `app/jobs/email_campaigns/reputation_evaluation_job.rb`
- `app/models/email_campaign.rb`
- `app/models/email_event.rb`
- `app/models/email_provider_state.rb`
- `app/models/email_reputation_audit.rb`
- `app/models/email_reputation_state.rb`
- `app/policies/email_campaign_policy.rb`
- `app/policies/email_reputation_policy.rb`
- `app/services/email_campaigns/delivery_engine.rb`
- `app/services/email_campaigns/direct_inbox/delivery_engine.rb`
- `app/services/email_campaigns/direct_inbox/recipient_sender.rb`
- `app/services/email_campaigns/guardrail.rb`
- `app/services/email_campaigns/reputation/admission.rb`
- `app/services/email_campaigns/reputation/campaign_delivery_lock.rb`
- `app/services/email_campaigns/reputation/evaluation_queue.rb`
- `app/services/email_campaigns/reputation/evaluator.rb`
- `app/services/email_campaigns/reputation/legacy_decision.rb`
- `app/services/email_campaigns/reputation/metrics.rb`
- `app/services/email_campaigns/reputation/observation.rb`
- `app/services/email_campaigns/reputation/payload.rb`
- `app/services/email_campaigns/reputation/policy.rb`
- `app/services/email_campaigns/reputation/provider_config.rb`
- `app/services/email_campaigns/reputation/provider_gate.rb`
- `app/services/email_campaigns/reputation/provider_monitor.rb`
- `app/services/email_campaigns/reputation/provider_release.rb`
- `app/services/email_campaigns/reputation/snapshot.rb`
- `app/services/email_campaigns/ses/client.rb`
- `app/views/api/v1/accounts/email_campaigns/campaigns/_campaign.json.jbuilder`
- `config/routes.rb`
- `config/schedule.yml`
- `db/migrate/20260916121000_create_email_reputation_states.rb`
- `db/migrate/20260916121100_index_email_reputation_cohorts.rb`
- `db/migrate/20260916121200_protect_email_reputation_history.rb`
- `docs/audit/436-reputation-manifest.md`
- `docs/audit/436-reputation.md`
- `docs/email-campaigns/reputation.md`
- `lib/custom_exceptions/email_reputation_blocked.rb`
- `lib/custom_exceptions/email_reputation_configuration.rb`
- `lib/custom_exceptions/email_reputation_override.rb`
- `spec/requests/api/v1/accounts/email_campaigns/reputation_spec.rb`
- `spec/services/email_campaigns/reputation/admission_spec.rb`
- `spec/services/email_campaigns/reputation/campaign_delivery_lock_spec.rb`
- `spec/services/email_campaigns/reputation/concurrency_spec.rb`
- `spec/services/email_campaigns/reputation/delivery_spec.rb`
- `spec/services/email_campaigns/reputation/evaluator_spec.rb`
- `spec/services/email_campaigns/reputation/feedback_spec.rb`
- `spec/services/email_campaigns/reputation/metrics_spec.rb`
- `spec/services/email_campaigns/reputation/policy_test.rb`
- `spec/services/email_campaigns/reputation/provider_concurrency_spec.rb`
- `spec/services/email_campaigns/reputation/provider_config_test.rb`
- `spec/services/email_campaigns/reputation/provider_gate_spec.rb`
- `spec/services/email_campaigns/reputation/provider_monitor_spec.rb`
- `spec/services/email_campaigns/reputation/provider_release_spec.rb`
- `spec/services/email_campaigns/reputation/retention_spec.rb`
