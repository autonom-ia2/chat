# Reputação e admissão de campanhas — #436

Backend em revisão. Correções locais de PR439/P1-03 e P1-04 em 2026-09-17: sincronização provider/admissão e bloqueio monotônico sob avaliações superseded. Validação desta rodada limitada a sintaxe, RuboCop e testes puros; novas regressões PostgreSQL aguardam o parent, assim como rebase após PR438 e revisão integrada. Não há declaração de prontidão para merge/deploy. Evidência e handoff em [436-pr439-concurrency-blockers.md](../audit/436-pr439-concurrency-blockers.md); histórico anterior em [436-pr1-review-fixes.md](../audit/436-pr1-review-fixes.md).

## Métricas e política efetivamente aplicada

`Metrics` conta destinatários SES do tenant com aceite confirmado (`sent_at`) na coorte inclusiva de sete dias. Não inclui claim ambíguo sem aceite, DirectInbox, outro tenant ou envio futuro. Feedback tardio pertence à coorte do envio. Uma consulta agrupada calcula todas as contagens por destinatário, deduplicando notificações.

Classificação local corrigida conforme as fontes AWS verificadas pelo parent em 2026-09-16 (sem consulta de rede nesta rodada):

| Subtipo de bounce | Contagem local e fingerprint |
| --- | --- |
| `Permanent/Suppressed` (lista global) | `permanent` + `bounced` + fingerprint nocivo; não é prova de mailbox inexistente |
| `OnAccountSuppressionList` | `provider_prevented`; fora de `permanent`, `bounced` e fingerprint nocivo |
| `OnTenantSuppressionList` | `provider_prevented`; fora de `permanent`, `bounced` e fingerprint nocivo |
| `EmailValidationSuppressed` | `provider_prevented`; prevenção do provedor, sem tentativa de entrega |
| `UnsubscribedRecipient` | `provider_prevented`; opt-out, sem tentativa de entrega nem impacto na reputação do remetente |

A [documentação da lista global SES](https://docs.aws.amazon.com/ses/latest/dg/sending-email-global-suppression-list.html) informa que `Suppressed` conta na taxa de bounce da conta e na quota. A [documentação de notificações](https://docs.aws.amazon.com/ses/latest/dg/notification-contents.html) distingue as listas de conta/tenant, que não contam nessa taxa, e o opt-out `UnsubscribedRecipient`. O [conteúdo dos eventos Firehose](https://docs.aws.amazon.com/ses/latest/dg/event-publishing-retrieving-firehose-contents.html) documenta `EmailValidationSuppressed`. Os quatro subtipos de prevenção ficam também fora de `transient` e `unknown`; o aceite SES continua no denominador local `sent`.

Permanentes genéricos e `Suppressed` não provam endereço inválido ou `NoEmail`. A classificação de bounce foi preservada.

Para **Complaint**, `complaintSubType=OnAccountSuppressionList/OnTenantSuppressionList` significa prevenção sem tentativa nem nova reclamação. As fontes [notification-contents](https://docs.aws.amazon.com/ses/latest/dg/notification-contents.html) e [sending-email-suppression-list](https://docs.aws.amazon.com/ses/latest/dg/sending-email-suppression-list.html) foram verificadas pelo parent em **2026-09-17**, conforme a instrução recebida; não houve consulta de rede nesta rodada. Esses eventos não entram em `complaints`, taxa, alerta de spam ou fingerprint nocivo, e não revogam override por novo feedback nocivo. `provider_prevented` agora conta destinatários distintos com prevenção de bounce **ou** complaint, uma vez por destinatário na coorte. O denominador `sent` continua sendo o aceite local confirmado, sem pretensão de reproduzir a métrica oficial AWS.

SNS mantém o `EmailEvent` bruto com o enum `complaint=4`, mas grava bloqueio forte `provider_suppression` no registro durável e no espelho de supressão, com status `suppressed`. Estados `unsubscribed`/`complained` e razões mais fortes são preservados. Replays não duplicam evento, ocorrência ou versão de feedback. Complaint sem subtipo, com `null` ou subtipo desconhecido continua reclamação real; nunca inferir prevenção a partir de outros subtipos de bounce.

Contrato público para relatórios/backfill: `EmailCampaigns::ComplaintClassifier::PREVENTED_SUBTYPES` contém somente os dois subtipos acima. `.provider_prevented?(complaint)` e `.real_complaint?(complaint)` recebem o objeto `complaint` com chaves string, ou `nil`, **não** o envelope. `PROVIDER_PREVENTED_SQL` e `REAL_COMPLAINT_SQL` são predicados SQL completos, incluindo `event_type = 4` e extração de `payload`; `PREVENTED_SUBTYPE_SQL` testa somente o subtipo com `COALESCE`, portanto não perde missing/null. São expressões sobre colunas não qualificadas de `email_events`, para uso em relações sem ambiguidade de nomes. `Metrics::COUNT_FILTERS[:complaints]` e `#harmful_feedback_fingerprint` usam `REAL_COMPLAINT_SQL`; `COUNT_FILTERS[:provider_prevented]` combina prevenção de bounce e complaint.

**Integração pendente do parent:** propagar esse contrato para `436-reports-integration` e os contadores derivados. Nesta worktree, `EmailCampaign#event_counters` ainda calcula `complained` contando todo evento bruto do tipo complaint, e `#refresh_counters!` persiste esse valor em `complained_count`; ambos estão fora do escopo desta correção. O contador de produto deve usar `REAL_COMPLAINT_SQL` e preservar sua regra de deduplicação. Sem essa propagação, esse contador ainda pode rotular prevenção como reclamação. Nenhum backfill, enum, API de provedor ou fonte de outra worktree foi alterado.

| Sinal local | Política nova padrão |
| --- | --- |
| Permanentes >=2% | `warning` |
| Permanentes >=4% | `high_risk` |
| Permanentes >=5%, pelo menos cinco | pausa |
| Qualquer complaint | `spam_alert=true` |
| Complaints >=0,05% | `attention` |
| Complaints >=0,1%, pelo menos um | pausa |

Comparações usam `BigDecimal`, sem arredondamento prévio. Taxas são proporções (`0.05` = 5%). Denominador zero retorna taxas nulas e não autoriza liberação de bloqueio existente. `86` aceites, quatro permanentes e um transitório: alto risco, sem pausa nova. `100/5`: pausa nova.

O escopo publicado `local_ses_sending_cohort` identifica a métrica local de sete dias. Ela não reproduz a amostra representativa nem os denominadores da reputação oficial AWS SES. O monitor lê as taxas oficiais separadamente; a correção de subtipos não transforma a taxa local em taxa AWS.

| Modo | Decisão aplicada |
| --- | --- |
| `shadow` (default) | preserva bloqueios e aplica regra legada; calcula recomendação nova |
| `warning` | mesma regra legada, com alertas auditados |
| `enforce` | aplica a política nova; preserva bloqueios históricos até revisão explícita |

Regra legada: pelo menos 50 aceites e bounces distintos **>5%** ou complaints **>0,3%**. A retomada em shadow/warning também deve satisfazer essa regra: `100` aceites, seis transitórios e zero permanentes continuam protegidos. Uma reavaliação nunca libera a proteção. A liberação normal exige decisão efetiva segura, pelo menos 50 aceites, permanentes abaixo de warning e zero complaints. Uma coorte que envelheceu até zero não comprova remediação. Exceção ativa de SuperAdmin autoriza admissões limitadas mantendo `blocked` e flag legada.

Configuração inválida falha com código técnico. Defaults estão em `.env.example`; não há endpoint para desligar checagens ou mudar limiares.

## Incidentes e retenção

`EmailReputationState` mantém avaliação atual e snapshot do **incidente mais recente**. Enquanto o incidente está bloqueado, `triggered_at/trigger_snapshot` são imutáveis no modelo e no PostgreSQL. A liberação preserva esse snapshot, os eventos e as contagens do histórico; não reinicia a janela nem zera a taxa. Uma nova pausa posterior cria novo timestamp, contagens e motivo; cada pausa permanece imutável em `EmailReputationAudit`.

Flag legada com `at` ISO8601 válido e não futuro conserva a data original. Datas ausentes, malformadas ou futuras usam o instante da incorporação. As métricas/política originais desconhecidas ficam `null`; nunca se rotulam contagens atuais como contagens iniciais do legado. Texto arbitrário da flag legada não é copiado para o payload público.

Estado pertence à conta, com FK **ON DELETE CASCADE**. Auditoria é append-only e retém `account_id/actor_id` lógicos **sem FKs restritivas**, mesmo após excluir conta ou usuário. Eventos globais usam `provider_key`, sem account. Não há exclusão de auditoria na UI/API normal, nem `dependent: :destroy` para contornar o trigger. Snapshots contêm contagens, códigos, política e motivo operacional; nenhum endereço ou dado de cliente é coletado. Operadores não devem inserir PII em motivos. Não foi criado expurgo automático de auditoria.

Migrações ainda não implantadas, renomeadas para evitar colisão com higiene; classes mantidas:

- `20260916121000_create_email_reputation_states.rb`
- `20260916121100_index_email_reputation_cohorts.rb`
- `20260916121200_protect_email_reputation_history.rb`

A última base validada pelo parent é o JSON limpo de 461 exemplos citado acima. Este agente não executou migração nem editou schema; nova validação Rails/DB após integração continua a cargo do parent.

## Concorrência, custo e fila

`Observation` reserva uma geração monotônica em lock curto de estado; coleta métricas e fingerprint **fora** de locks de conta/estado. Publicação adquire account → state e verifica geração e versão de feedback. Observações ultrapassadas retornam `reputation_evaluation_superseded` e nunca autorizam retomada/override nem publicam métricas como atuais. Exceção conservadora: em `enforce`, uma observação que por si só satisfaz a pausa pode mudar um estado ainda não bloqueado para `blocked=true`, com `level=paused` e flag legada. Seu snapshot imutável guarda as métricas observadas, política, geração, versão observada de feedback e `superseded=true`. Não altera `current_metrics`, `policy`, `evaluated_at` nem `evaluated_feedback_version`; não substitui incidente já bloqueado. Portanto, `current_metrics` continua sendo a última avaliação publicada, enquanto o snapshot explica o bloqueio novo. Feedback contínuo não impede mais essa pausa conservadora.

`EmailCampaign#resume!` coleta antes de qualquer lock externo. Retomada SES e override seguem account → state → provider → campaign, omitindo provider quando o monitor está desligado; DirectInbox não adquire provider. Avaliação simples não precisa do lock global. Monitor e liberação global adquirem apenas provider depois da coleta, sem buscar locks de tenant em seguida.

`EmailReputationState.for_account(account_id)` mantém leitura rápida quando o estado existe. Na primeira criação, adquire `Account.with_lock` **antes** de `create_or_find_by!` ocupar a chave única e resolver a FK. Evita o ciclo entre SNS segurando Account e a avaliação segurando a inserção ainda não confirmada. Observation e Queue não adquirem Account depois de travar um estado existente; SNS entra pelo wrapper Account → state → campaign → recipient. Escritores compostos futuros devem entrar por `EmailEvent.with_recipient_feedback_locks` antes de qualquer lock de filho. Criação avulsa de EmailEvent invalida em `before_save`, antes de inserir o evento/FK do recipient; nunca mover essa invalidação apenas para pós-commit.

A versão de feedback é invalidada **dentro da transação do EmailEvent, em before_save**. O callback pós-commit apenas solicita a fila. Isso fecha a janela entre commit do sinal nocivo e enqueue. Correções de classificação também invalidam. **Integração de higiene que use insert_all/update_all/SQL deve chamar `EvaluationQueue.invalidate(account_id)` na mesma transação e `request(account_id)` após commit.** Não envolver o avaliador inteiro em transação/lock externo. Se outro fluxo passar a segurar recipient/campaign ao gravar feedback, preservar a ordem de locks compartilhada na integração.

`EvaluationQueue` usa lease persistida de 300 segundos com token. Feedbacks dentro da lease são agrupados; versão nova durante coleta invalida a publicação de métricas e conclusão agenda uma avaliação seguinte. O bloqueio monotônico não reconhece feedback como avaliado. Observação superseded solicita follow-up após commit; uma lease ativa agrupa esse pedido, e `finish` considera tanto feedback não avaliado quanto geração reservada ainda não publicada. Um token antigo não conclui a lease sucessora. Job com token substituído não coleta. Falha de enqueue/processo não apaga o sinal: próximo feedback após expiração e sweep periódico recuperam. Há no máximo um novo enqueue por conta durante cada lease, mais o sucessor necessário após conclusão; não se promete entrega exatamente uma vez. Sweep de dez minutos cobre campanhas, estados e flags antigas, inclusive contas já pausadas.

Fingerprint nocivo considera envios aceitos de todo o histórico, incluindo feedback tardio fora da coorte. SQL deduplica destinatário/tipo/classificação, calcula contagem e duas somas numéricas de hashes, devolvendo três valores fixos para SHA256. Não usa `pluck` de histórico, arrays nem JSON agregados. Duplicatas não mudam o conjunto; correções de classificação e novos outcomes mudam. O custo de leitura SQL ainda cresce com o histórico; memória da aplicação/resultado não cresce. Reavaliação é assíncrona, não executada por destinatário.

## Admissão e entrega

`Admission` consulta proteção persistida no início, em cada iteração SES e antes do claim. Faz leituras locais, checagem de supressão e transição condicional; nenhuma agregação, DNS ou HTTP. Na autorização final SES (e no gate de compatibilidade), a ordem é account → state → provider → campaign → recipient quando o monitor está habilitado. A linha global é obtida por lookup/`create_or_find_by!`, sob índice único, e fica travada até o commit do claim. Prepare, estacionamento, recibos e demais mutações não adquirem esse lock global; preservam account → state → campaign → recipient. Espelho da flag usa operações JSONB atômicas sobre a coluna corrente, preservando outras chaves.

`CampaignDeliveryLock` usa advisory lock de sessão PostgreSQL, exclui outro processo/conexão e rejeita reentrada local da mesma campanha. Libera em exceção; perda da conexão libera sessão. Exige afinidade de sessão, incompatível com transaction pooling do PgBouncer. Não é um limite global de vazão SES.

Envio já admitido pode estar em voo quando um bloqueio é publicado. Se o monitor confirma o bloqueio antes de a admissão obter o lock global, o claim não autoriza. Se a admissão já possui esse lock, o monitor espera seu commit; o claim pertence legitimamente aos envios em voo. Renderização, envio SES, coleta SES/CloudWatch e enqueue externo ficam fora dessas transações. Timeout/5xx ambíguo não reenfileira automaticamente; só rejeição explícita de throttling pode voltar a pending. Falha de persistência após aceite mantém o claim. Campanha com aceite, claim/falha ambígua ou eventos não pode ser apagada pela API.

DirectInbox compartilha proteção e orçamento do tenant, conserva seus limites e supressão, e não usa o bloqueio global SES.

## Exceção e proteção global

Exceção de tenant exige **SuperAdmin persistido**, motivo de 10–500 caracteres, duração de 1–3600 segundos e orçamento de 1–50 novas admissões. Roles/campos de request não conferem autoridade. Nunca limpa supressões ou supera bloqueio global. Expiração e esgotamento valem na próxima admissão sem depender de sweep; novo feedback nocivo revoga ao publicar reavaliação. Ator, motivo, orçamento e fingerprint só ficam disponíveis ao operador autorizado, nunca no payload comum.

Monitor global é desligado por padrão. Monitor desligado/parado ou ausente não constitui evidência de saúde; esta revisão não altera esse status operacional. Chave é AWS account explicitamente configurada + região SES, sem escopo de tenant. Coleta read-only: SESv2 GetAccount (`SendingEnabled/EnforcementStatus`) e CloudWatch GetMetricStatistics (`Reputation.BounceRate/ComplaintRate`, Average, período 300s, datapoint mais recente). Não usa dados locais como reputação oficial. Clientes injetáveis; timeouts SES 5s/10s, CloudWatch 5s/10s e uma repetição do SDK. Não foram executadas consultas reais.

Guardas preventivas padrão: bounce **>=0.05**, complaint **>=0.001**. `ProviderConfig` permite valores positivos, finitos e **mais conservadores**, nunca maiores que esses defaults. `PROBATION`, `SHUTDOWN` e sending disabled sempre bloqueiam. Ausência de ponto, erro, data futura ou telemetria antiga não são saúde. Freshness padrão 900s, validada entre 300–3600s. `UNKNOWN_ACTION=allow` não apaga latch conhecido.

Após bloqueio, uma leitura saudável apenas torna a condição elegível para revisão: `status=healthy` pode coexistir com `blocked=true`. Monitor não libera latch. A liberação exige `ProviderRelease`, SuperAdmin real, motivo e **nova consulta** com sending habilitado, enforcement HEALTHY e ambas as taxas frescas abaixo dos limiares. Registra `provider_released`. Uma nova transição a bloqueio registra `provider_blocked`, sem payload bruto do provedor. Erros persistem só classe, sem mensagem privada.

`EMAIL_REPUTATION_PROVIDER_BLOCK=true` é emergência de configuração e não pode ser superada por API. A liberação não funciona com monitor desligado, telemetria desconhecida/antiga ou SES desabilitado. `manual_block` durável só pode ser liberado pela mesma revisão saudável. Não há endpoint que habilite SES ou altere configuração AWS.

## API para integração

Base `/api/v1/accounts/:account_id/email_campaigns`, usando autenticação/autorização existentes:

| Rota | Contrato |
| --- | --- |
| `GET /reputation` | admin do tenant; `{protection, state}` sanitizados, sem histórico |
| `POST /reputation/reevaluate` | admin; `{protection: avaliação}` |
| `POST /campaigns/:id/reevaluate` | admin; avaliação no escopo SES/DirectInbox da campanha |
| `POST /campaigns/:id/resume` | sucesso preserva `{payload: campaign}`; negativa 422 com proteção |
| `POST /reputation/override` | SuperAdmin com acesso ao tenant; `reason`, `duration_seconds`, `message_budget` |
| `GET /reputation/history` | **SuperAdmin**; últimos 100 registros apenas desse tenant, inclui detalhe operacional |
| `POST /reputation/provider_release` | **SuperAdmin** com acesso ao tenant; ação global, `reason`; nova consulta e liberação auditada |

Avaliação pública: `{blocked, level, evaluated_at, current_metrics, policy, trigger_snapshot, override_active, resume_allowed, protection?}`. Sem `override`, atores, notas internas ou orçamento. `trigger_snapshot` só expõe `triggered_at/code/metrics/policy`. `resume_allowed` considera regra efetiva e provider; GET mostra estado persistido, POST reavalia. `blocked` é o latch do tenant, não do provider.

Proteção rápida: `{kind: reputation|provider|technical, code, triggered_at?/observed_at?, overridable}` ou null. Nunca expõe `EmailProviderState.as_json`, AWS account, manual_reason ou dados de outro tenant.

Códigos: `email_campaign.protected`, `email_campaign.invalid_override`, `email_campaign.provider_release_denied`, `email_campaign.configuration_invalid`, `email_campaign.delivery_history_retained`; observação ultrapassada: `reputation_evaluation_superseded`; liberação global bem-sucedida: `{code: 'provider_released'}`. Pundit negado retorna **401**, conforme handler existente. Campanha de outro tenant continua **404**. Não houve mudança no contrato global de auth.

## Integração, validação e rollback

Preservar patches de higiene, relatório e UI do parent nos arquivos sobrepostos, sobretudo EmailEvent, Guardrail, engines, campaign model/controller, routes, schedule e `.env.example`. `account.rb` não foi alterado nesta revisão. Não há overlay Enterprise correspondente encontrado nas buscas locais.

Specs incluem duas conexões PostgreSQL com PIDs diferentes e fixtures transacionais desativadas apenas nos testes concorrentes: 50 mil sends, barreiras de coleta/commit, retomada real, publicação fora de ordem, polls concorrentes e advisory lock. A regressão de primeira criação segura Account numa sessão e confirma via `pg_blocking_pids`/`pg_stat_activity` que a outra espera no lock de Account, antes do INSERT; a dona processa SNS e a avaliação publica evento/versão/geração/snapshot preservados. Queue.invalidate/request também são cobertos. Limpeza fica nos registros sintéticos criados; auditorias append-only retêm IDs lógicos. **Todos os testes anteriores foram preservados; as regressões Rails adicionadas nesta rodada ainda não foram executadas.**

Parent: validar o conjunto integrado no DB sintético com as três migrações revisadas, rodar regressões completas, integrar higiene/UI, revisar diff e atualizar issue/PR/Project. Sem commit nesta entrega. Merge/deploy dependem de aprovação explícita.

Rollback de aplicação deve conservar tabelas/triggers/auditoria. Flags espelhadas mantêm bloqueio nos binários antigos, mas binário anterior não tem guardas do loop nem bloqueio global. Voltar exige procedimento aprovado de interrupção de novos envios e drenagem, ou retenção do patch de admissão. Desligar monitor não libera proteção persistida. Nenhuma migração, IAM, SMTP, deploy ou ação operacional foi executada aqui.
