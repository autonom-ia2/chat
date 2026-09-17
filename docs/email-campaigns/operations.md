# #436 — manutenção, aceitação e rollback

PR4 conecta manutenção explícita por conta para recuperar proteção histórica. Não cria backfill em migration, boot ou deploy; não descobre contas, consulta AWS/DNS/SMTP, envia mensagens, reavalia reputação ou retoma campanhas. Código local e specs escritos não comprovam operação em produção. Evidência desta integração: [436-operations-integration](../audit/436-operations-integration.md). A revisão anterior permanece em [436-operations](../audit/436-operations.md).

## Dependências e escopo final

PR0 fornece higiene, registry e bridge legado. PR1 fornece reputação/provedor, protocolo `Account → state → campaign → recipient` e os classificadores compartilhados. Reports/UI serão integrados pelo parent antes da aceitação final. PR4 usa os modelos reais de reputação sem escrever neles.

**Dependência concreta de PR1:** `EmailCampaigns::ComplaintClassifier.provider_prevented?(complaint)` foi lido em `../436-delivery-integration/app/services/email_campaigns/complaint_classifier.rb`. Recebe o objeto `complaint`, não o envelope. O parent deve trazer esse arquivo antes dos testes finais. Não há cópia local nem fallback alternativo. Sua ausência faz o batch falhar de forma limitada; não classifica prevenção como novo spam silenciosamente.

O bloqueio de endereço é da **conta Chat2You**, independente do domínio remetente. O termo provider_suppression descreve a origem da prova; não cria bloqueio do endereço em outras contas. `EmailReputationState` e pausa legada são da conta. `EmailProviderState` é do provedor/conta AWS/região, compartilhado pelas contas que o usam: manutenção não o libera nem o modifica. DirectInbox compartilha proteção do tenant, mas não o breaker SES, conforme o guardrail existente.

## API conectada

As três rotas reais estão em `config/routes.rb`, no namespace `api/v1/accounts/:account_id/email_campaigns`:

| Método e caminho relativo | Comportamento |
| --- | --- |
| `POST maintenance/backfills` | Cria ou recupera run idempotente, 202. Preview por padrão. |
| `GET maintenance/backfills/:id` | Retorna progresso da conta autenticada, 200, sem mutações. |
| `POST maintenance/backfills/:id/retry` | Body/query vazio; retry explícito de run failed do mesmo ator, 202. |

Autenticação e acesso à conta seguem middleware/Pundit existentes. Exigem usuário cujo **tipo persistido é exatamente SuperAdmin**, conta ativa e associação atual em `account_users`. `becomes(SuperAdmin)` ou parâmetro de papel não promove usuário. Uma instância Ruby carregada como User com tipo persistido SuperAdmin continua válida. Start/Retry também verificam essas condições sem depender do controller, com consultas sem cache. Cada batch, inclusive preview e retomada de lease abandonado, revalida o ator e o acesso atual; apply revalida o flag. Revogação durante um batch pode permitir que esse batch limitado termine; impede o próximo.

As features existentes `CRM_KANBAN_ENABLED` e `EMAIL_CAMPAIGN_ENABLED` precisam disponibilizar as rotas. Nenhuma mudança de auth, plano ou credenciais faz parte do pacote.

Create permite somente `mode`, `confirm`, `reason`, `idempotency_key`, `batch_size`. Rejeita parâmetros adicionais no body e query, inclusive account_id/actor_id/role/provider/kind/dry_run. Tenant vem da rota autenticada. Retry não aceita parâmetros operacionais. GET não cria runs, não retorna evidência bruta e não oferece release/override.

| Entrada | Contrato exato |
| --- | --- |
| `mode` | Omitido ou string `dry_run` = preview. Só string `apply` seleciona aplicação. |
| `confirm` | Apply exige a string exata `apply`. Booleanos, `true`, espaços, caixa diferente e ausência são inválidos. Preview rejeita confirm. |
| `reason` | String obrigatória, 1–200 caracteres após trim. Motivo operacional sem dados pessoais; guardado no run privado. |
| `idempotency_key` | String obrigatória, 8–100 caracteres ASCII alfanuméricos, `_` ou `-`. Única por conta. |
| `batch_size` | Padrão 100; inteiro ou string decimal, 1–500. |
| `EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED` | Padrão `false`, documentado em `.env.example`. Aceita apenas strings exatas `true`/`false`; outra entrada é erro. |

Preview grava somente seu run/progresso/outbox. Não escreve fontes, supressões, auditoria de supressão, reputação, campanhas ou destinatários. Exemplo de body sintético:

```json
{"reason":"Revisão operacional sintética","idempotency_key":"preview_436_001","batch_size":100}
```

Depois de preview, revisão e aprovação operacional separada para configuração/apply, usar nova chave, `"mode":"apply"` e `"confirm":"apply"`. A API não certifica aprovação humana nem exige vínculo artificial com preview. Preview nunca é convertido. Apply fixa seu próprio horizonte, portanto inserções entre os dois runs podem mudar contagens. Reutilizar chave com modo/motivo/batch diferentes retorna `idempotency_conflict`; repetição da chave original não reinicia run terminal. Preview vazio ou failed não é aplicação bem-sucedida nem prova de reputação saudável.

## Classificação histórica e proveniência

Preview e apply usam a mesma `Maintenance::Evidence` e os mesmos classificadores compartilhados, sem classificador paralelo de simulação.

| Prova histórica | Proteção local |
| --- | --- |
| Bounce `Permanent/General` ou `Permanent/NoEmail` | hard_bounce, classification=permanent, reason_code=permanent_failure. NoEmail é falha genérica, não afirma caixa inexistente. |
| Bounce global `Permanent/Suppressed` | provider_suppression, classification=permanent. Continua permanente prejudicial à métrica; não é prevenção sem tentativa. |
| Bounce `OnAccountSuppressionList`, `OnTenantSuppressionList`, `EmailValidationSuppressed` | provider_suppression durável, classification=unknown; prevenção sem tentativa. |
| Bounce `UnsubscribedRecipient` | unsubscribe, classification=unknown; preserva opt-out. |
| Complaint com `complaintSubType=OnAccountSuppressionList` ou `OnTenantSuppressionList` | provider_suppression, não novo spam/complaint. Usa o helper compartilhado de PR1. |
| Complaint normal ou subtipo ausente/desconhecido | complaint. |
| Evento unsubscribe | unsubscribe. |
| Transient, desconhecido ou outro evento | Avança cursor; não inventa permanente nem repete soft counts para fabricar quarentena. |
| Positivo legado de razão forte conhecida | Preserva provider_suppression/hard_bounce/complaint/unsubscribe/manual. Razão livre vira prova limitada legacy_permanent_positive/manual; texto antigo não é copiado. |

Status do destinatário sozinho não prova bounce permanente. Registry é o único escritor de estado, auditoria e positivo legado; mantém sua prioridade. Provider block nunca sobrescreve unsubscribe, spam ou hard mais fortes. Eventos reais não são reescritos, e timestamps originais são preservados na prova. Estado temporário/quarentena já existente não é liberado.

Chaves seguem o escritor ao vivo: `ses:<messageId>:bounce`, `ses:<messageId>:complaint`, `unsubscribe:<recipient_id>`. SES usa `mail.messageId`, depois `recipient.ses_message_id`; sem chave utilizável de até 200 caracteres, usa `historical:email_event:<id>`. Fallback deduplica a linha, sem prometer dedupe de uma futura notificação de identificador antes desconhecido. Legado usa `historical:email_suppression:<id>`.

Auditoria usa source=backfill, occurred_at original, IDs da origem/campanha/run e códigos locais. Metadados permitidos: historical_event_id, legacy_suppression_id, maintenance_run_id, classification, reason_code e evidence_code. Não copiam endereço, payload, chave SES ou motivo livre. Motivo fica no run privado; endpoints e telemetria desta manutenção não o devolvem. Não fornecer PII no reason; esta regra não é promessa de filtragem de todo log HTTP da aplicação.

Horizontes são os máximos de EmailEvent.id e EmailSuppression.id da conta no início. Eventos atravessam recipient → campaign → account; provas revalidam tenant. Não há corte por data: cobre histórico antigo até o teto. IDs não constituem snapshot imutável de conteúdo; edição/exclusão concorrente de linhas antigas pode mudar o que será lido. Inserções além do teto ficam para outro pedido explícito.

Contagens são **eventos/provas**, não endereços únicos ou taxa SES. events_processed/legacy_rows_processed contam linhas; eligible_events inclui prevenções/opt-out. already_protected_events/unprotected_candidate_events são observações por evento antes do registry; preview pode contar repetidamente o mesmo candidato. block_records_created/legacy_rows_mirrored contam provas novas; duplicate_events/duplicate_legacy_rows contam chaves existentes. skipped_unknown_events/skipped_temporary_events/skipped_other_events contam ignoradas. A autoridade de dedupe é o resultado do registry; não somar runs como pessoas.

## Jobs, limites e recuperação

`config/schedule.yml` conecta `EmailCampaigns::ProtectionBackfillReconcileJob` a cada minuto em `housekeeping`, fila já existente. O cron só seleciona até 100 **runs existentes** vencidos, ordenados por prazo/ID. Não examina sent history, descobre contas, cria pedidos ou aplica sem solicitação. Independe do flag de apply para recuperar previews. Apply desligado falha no worker com apply_disabled; cron nunca liga o flag. Não há novo serviço de monitoramento, infraestrutura ou IAM.

Cada job consome até batch_size (máximo 500) e cede após orçamento de 10 segundos entre linhas. Uma consulta em andamento não tem timeout garantido por esse orçamento. Cada linha grava registry + contagem + cursor na mesma transação. Lock local é Account → run → registry/supressão. Existe caminho inverso real a evitar: exclusão da conta bloqueia Account antes do cascade em runs. Por isso processamento não segura run enquanto espera Account. Registry pode adquirir Account novamente na mesma transação. Não adquire locks de reputação/campanha/destinatário; não inverte o protocolo compartilhado Account → state → campaign → recipient. Claim/finish/dispatch/retry fazem locks curtos do run sem tentar adquirir Account depois. Sem rede sob locks.

Lease dura 2 minutos e renova a cada linha. Token é conferido sob lock antes da prova; holder antigo não escreve após reclaim. Máximo de 3 tentativas por batch; batch concluído zera esse contador. Máximo de 3 enqueues sem claim, intervalo de 5 minutos entre reservas. Erros/crashes repetidos terminam em failed. Cada run admite no máximo **3 pedidos explícitos de retry**, contados persistentemente por retry_count; concorrentes serializam sob lock. Retry preserva modo, teto, cursor, chave, motivo, provas e erro acumulado; renova somente o orçamento de batch/enqueue. Um novo run exige pedido/chave novos e mantém dedupe do registry.

`after_save_commit` publica primeira execução, continuação e retry só após commit externo. Rollback não publica. O filtro usa estado pending/prazo duráveis, pois reload pode limpar dirty tracking. Reserva futura evita recursão. Cron recupera commit sem callback, enqueue falho, mensagem perdida e lease vencido. Run removido por cascade não é recriado. Nenhum job chama envio, unpause, release ou reavaliação.

## Erros, saúde e telemetria

| Superfície | Contrato |
| --- | --- |
| Request inválido | 422: unsupported_parameter, invalid_mode, invalid_confirm, invalid_reason, invalid_idempotency_key, invalid_batch_size, idempotency_conflict, apply_disabled, run_not_failed, actor_mismatch, retries_exhausted. |
| Config inválida | Request: 422 invalid_backfill_configuration; worker: invalid_configuration. |
| Worker/outbox | batch_failed sem mensagem de exceção; actor_unavailable, apply_disabled, attempts_exhausted, enqueue_failed, enqueue_exhausted. |
| Permissão | Handler existente 401 para não autenticado, não SuperAdmin, associação removida ou conta suspensa. Token API pode receber 403 pelo plano. Features indisponíveis ou run ausente/de outra conta: 404. |

Status e retry não desbloqueiam conta/campanha/provedor. Outro SuperAdmin autorizado pode ler o run, mas não assumir retry do autor. GET retorna allowlist: IDs da conta/run, modo, fase/estado, cursores/tetos, contagens, tentativas/retry_count, códigos e timestamps; não revela ator, motivo, idempotency_key, lease_token ou estado de outras contas/provedor.

Telemetria usa Rails.logger estruturado e `ActiveSupport::Notifications` existentes: `email_protection.batch_finished`, `batch_failed`, `enqueue_failed`, `run_failed`. Payload contém somente progresso público. Observar queue housekeeping, prazo vencido, lease sem renovação, cursor sem avanço, duração, erros e terminais. Alarmes/assinantes ficam no mecanismo existente; nenhum coletor externo é provisionado. As notificações não substituem outbox nem histórico persistido.

Saúde local não é certificação de domínio ou reputação oficial. Métricas locais baseadas em sent_at/eventos e métricas SES têm escopos distintos. Reports deve separar permanente global Suppressed de provider prevention e usar o mesmo ComplaintClassifier. Parent valida essa compatibilidade após reports/UI. Monitor de provedor é controlado separadamente por EMAIL_REPUTATION_PROVIDER_MONITOR; IAM e pré-condições estão em [reputation.md](reputation.md), sem alteração nesta PR. Telemetria ausente/atrasada não significa saudável. Preflight DNS não prova caixa, consentimento ou entrega; não faz SMTP probing.

## Rollout por marco e gates em cada merge

Fluxo externo do parent: Issue → Branch → PR → Project update → Review → Approval → Merge → Deploy/Rollback plan. **Cada merge em main dispara blue-green nas duas stacks** segundo o contrato operacional do projeto; exigir aprovação antes do merge e observar as duas stacks antes do seguinte. Não equivale a verificação ao vivo feita nesta rodada.

1. PR0/higiene: migrations/registry/bridge e retenção; matriz de bounce e opt-out. Review, SQL isolado, regressões, plano de rollback e aprovação. Após deploy: saúde e smoke autorizado das duas stacks, sem limpar proteção.
2. PR1/reputação/provedor: locks, guards finais, ComplaintClassifier/PREVENTED, latched state e auditoria. Repetir todos os gates. Monitor permanece false até operação de configuração aprovada.
3. Reports/UI: denominadores locais versus oficiais, prevenção versus spam, escopos/permissões/ações. Repetir todos os gates, inclusive jornada real autorizada após deploy, antes da PR4.
4. PR4/manutenção: rotas/cron/env já ligados no código; migration de runs com retry_count, specs HTTP e concorrência SQL. Repetir gates após rebase, com apply=false. Parent atualiza schema no harness isolado e não reutiliza tabela de uma versão antiga da migration sem retry_count.
5. Shadow: EMAIL_CAMPAIGN_HYGIENE_MODE=shadow e EMAIL_REPUTATION_MODE=shadow, DNS=false, provider monitor=false, backfill=false. Conferir regressões de proteção e preview por conta solicitado explicitamente.
6. Warning: cada domínio tem flag independente; promover higiene/reputação para warning somente após evidência e aprovação da configuração. Não promove monitor, DNS ou backfill junto.
7. Enforce: cada flag muda separadamente após evidência/review/aprovação. Apply requer preview revisado, nova chave, confirmação exata e flag próprio; não depende implicitamente de warning/enforce. Monitor e DNS continuam opt-ins separados.

Em **cada** merge: código completo do marco → testes sintáticos/RuboCop e SQL/HTTP do parent → review → aprovação explícita → blue-green → saúde das duas stacks → smoke autorizado da jornada/negativas → comparação de pausas, latches e auditoria → observação → decisão de prosseguir/rollback. CI verde isoladamente não prova jornada nem autoriza o próximo merge.

## Rollback e retenção

Desligar apply impede novos batches apply; um já iniciado pode terminar. Drenar jobs e suspender apenas a entrada de cron desta manutenção antes de remover classes no rollback de código, usando procedimento aprovado. Não apagar filas indiscriminadamente. Outbox preservada pode ser retomada após reupgrade explícito.

Rollback comportamental: higiene/reputação em shadow, DNS/monitor/backfill desligados separadamente. **Nenhuma volta a shadow libera latch histórico**, pausa manual/legada, bloqueio global, spam, hard, opt-out ou quarentena. Reavaliação/release são outros fluxos com suas próprias autorizações. Nunca retomar campanhas automaticamente nem reenviar para testar rollback.

Preservar tabelas, positivos legados, estados, quarentena, timestamps e auditoria completa. Não executar down, apagar histórico, limpar supressão ou resetar cursores/triggers. Migration de runs é irreversível; FK nova para Account usa ON DELETE CASCADE. Actor é referência lógica nullable, sem FK. Auditoria de supressão continua com referências lógicas sem FK restritiva; esta PR não muda retenção legada. Positivos fortes seguem visíveis ao leitor antigo. Se versão antiga não aplica quarentena, não retomar envios afetados até haver leitor compatível; preservar o estado sozinho não autoriza liberar essas mensagens.

## Aceitação automatizada local — execução pelo parent

Somente em harness já preparado, banco descartável exclusivo em loopback, credenciais sintéticas, filas de teste, PR1/classificador e migrations atuais. RAILS_ENV=test sozinho não garante isolamento. A suíte de concorrência exige conexões reais e não usa fixtures transacionais. Não apontar estes comandos a banco compartilhado/produção nem carregar env real.

```sh
eval "$(rbenv init - zsh)"
RAILS_ENV=test RBENV_VERSION=3.4.4 bundle exec rspec \
  spec/services/email_campaigns/maintenance \
  spec/controllers/api/v1/accounts/email_campaigns/maintenance_controller_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_backfill_spec.rb \
  spec/requests/api/v1/accounts/email_campaigns/maintenance_acceptance_spec.rb
```

Execução pendente, sem skip e sem remoção de casos. Conferir: rotas reais e negativas, confirmação/flag/permissões atuais, limites/idempotência, preview somente progresso, apply e reimport por outro domínio sem dispatch, proveniência sem PII, pausa/latch global versus conta, classificação de Complaint PREVENTED, prioridade de unsubscribe, histórico, cascade, after_commit/rollback, leases duplicados/abandonados, retries concorrentes e orçamento persistido. Parent adiciona os gates existentes de higiene, SNS, entrega, reputação, reports e UI ao aggregate. Não há comando manual de produção, SQL, console/runner, curl autenticado ou AWS neste runbook.
