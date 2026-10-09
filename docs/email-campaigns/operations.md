# Epic436 — operação, backfill e rollback

Este pacote acrescenta manutenção explícita de supressões históricas. Não inicia backfill em migration, boot, deploy ou varredura de contas. Não envia e-mail, consulta provedor/DNS, recalcula reputação, altera destinatários ou retoma campanhas. Os controles existentes continuam ativos em shadow. Saúde registrada no backend é informação interna, não uma pontuação oficial do domínio ou certificação de entregabilidade.

## Integração e sequência de rollout

Fluxo do integrador: issue436 → branch isolada → PR → atualização do Project → review independente → aprovação explícita de Rodrigo → merge → observação/rollback. Nenhuma dessas etapas externas foi executada por este pacote.

1. Integrar primeiro higiene/registry e sua migration aditiva: tabela legada `email_suppressions` contém apenas positivos permanentes; `email_suppression_states` guarda observações/quarentenas. Preservar compatibilidade OSS/Enterprise e do leitor antigo.
2. Integrar reputação/telemetria do workstream B conforme suas dependências; depois relatórios/UI que os consomem. Integrar esta manutenção no final, após o contrato corrigido do registry e a migração `20260916123000`.
3. **Cada merge em main aciona blue-green automaticamente nas duas stacks.** Review e aprovação são anteriores ao merge. Esperar saúde e smokes das duas stacks antes do próximo merge. Não tratar merge como uma operação sem deploy.
4. Começar com `EMAIL_CAMPAIGN_HYGIENE_MODE=shadow`, `EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED=false`, novo monitor de reputação desativado e `EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED=false`. O nome definitivo do flag do monitor e seu IAM vêm do workstream B; este pacote não os inventa.
5. Integrador executa migrations/testes apenas no banco isolado e autorizado, incluindo os specs novos, concorrência real, autenticação, regressões e verificações OSS/Enterprise. Validar smokes autorizados das rotas após wiring. Não usar produção para descobrir falhas de integração.
6. Só após preview e validação, a ativação exige **outra operação de configuração aprovada**. Não ativar automaticamente junto com o código; não usar console Rails, runner ou SQL manual de produção como interface operacional.

Nenhum servidor, conta AWS, banco compartilhado, segredo ou dado de cliente foi consultado durante esta implementação.

## Contrato que o integrador deve conectar

Rotas novas, dentro do namespace existente `api/v1/accounts/:account_id/email_campaigns`:

```ruby
post 'maintenance/backfills', to: 'maintenance#create'
get 'maintenance/backfills/:id', to: 'maintenance#show'
post 'maintenance/backfills/:id/retry', to: 'maintenance#retry'
```

Classe: `Api::V1::Accounts::EmailCampaigns::MaintenanceController`. Não há GET que crie runs, listagem irrestrita ou exportação de evidências/endereço. As rotas não foram editadas neste pacote. O controller desativa o wrapper JSON; create/retry rejeitam parâmetros desconhecidos no body/query, inclusive `account_id`, `actor_id`, `role`, `kind`, `provider` e `dry_run`. O tenant vem da rota autenticada.

Usar sessão/token de um **SuperAdmin persistido**, com acesso à conta pelo middleware existente (atualmente exige associação `account_users`). Administrador comum da conta não pode criar, repetir ou ler. O serviço verifica novamente o tipo persistido; parâmetros de papel não promovem o usuário. Pundit continua usando o handler global e retorna **401**, sem alteração do contrato global. Run de outra conta retorna **404** para operador autorizado da conta da URL. A feature principal também deve estar disponível pelos flags existentes `CRM_KANBAN_ENABLED` e `EMAIL_CAMPAIGN_ENABLED` para usar estas rotas.

| Configuração | Padrão | Contrato |
| --- | --- | --- |
| `EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED` | `false` | Apenas strings exatas `true`/`false`; outra entrada é erro. `true` permite solicitar/continuar apply, mas não cria runs. |
| Batch por requisição | `100` | Inteiro entre 1 e 500; acima/abaixo é rejeitado. |
| Scheduler do reconciliador | Não conectado | Integrador pode habilitar explicitamente uma entrada opt-in a cada minuto para `EmailCampaigns::ProtectionBackfillReconcileJob`, fila `housekeeping`. |

O reconciliador NÃO depende do flag de apply para recuperar simulações existentes. O gate opt-in da agenda pertence ao integrador; manter sem agenda até aprovação. Cada chamada examina até 100 runs vencidos, sem criar outros. Jobs rodam em `housekeeping`, já declarada no Sidekiq. Não conectar este job à migration, ao scheduler de envio ou a uma descoberta de contas.

## Preview e apply pela API

Enviar JSON no POST, usando o mecanismo de autenticação já aprovado (nunca copiar tokens para documentação/logs):

```json
{
  "reason": "epic436 revisão operacional aprovada",
  "idempotency_key": "epic436_preview_001",
  "batch_size": 100
}
```

Sem `mode`, o run é **dry_run**. Também aceita `"mode":"dry_run"`. `reason` deve ter 1–200 caracteres após trim, sem dados pessoais; `idempotency_key` deve ter 8–100 caracteres ASCII alfanuméricos, `_` ou `-`. Ambos são obrigatórios inclusive para preview. A resposta é 202 com ID, cursores, horizontes, contagens e estado; GET no ID acompanha progresso sem mutações.

Preview não escreve supressão/estado/auditoria de supressão, campanha, destinatário ou reputação. Escreve apenas o próprio run e seu progresso/fila. Revisar evidências sintéticas nos testes e contagens do preview, tenant, horizonte, desconhecidos e pausas antes de aprovar apply. Não há download de payloads ou endereços nesta API.

Após aprovação separada para ativar o flag, enviar outro POST com `"mode":"apply"` e **nova chave**, mantendo motivo explícito. Somente esta string exata seleciona apply. Um run dry_run nunca é convertido em apply. O novo apply captura seu próprio horizonte; eventos/positivos inseridos entre preview e apply podem mudar as contagens. Repetir a mesma chave e mesmos parâmetros devolve o mesmo run; reutilização com modo, motivo ou batch diferentes retorna 422 `idempotency_conflict`. Uma chave repetida não reinicia um run terminal.

**Confirmação explícita implementada:** `mode` deve ser a string exata `apply`, junto de motivo, chave válida, flag e SuperAdmin. Não existe parâmetro booleano de confirmação, conversão de preview, release ou override. A API não atesta aprovação humana nem exige vínculo com um preview anterior: revisar/aprovar é uma etapa operacional. `completed` com `dry_run=true` significa apenas simulação concluída; preview vazio ou failed nunca comprova apply, proteção acrescida ou reputação recuperada. Apply sem provas pode terminar com zero alterações.

Pré-condições verificadas novamente no início de cada batch apply: flag habilitado e `actor_id` ainda corresponde a SuperAdmin persistido. Desabilitar o flag faz próximos batches falharem com `apply_disabled`; um batch já iniciado pode terminar seu trabalho limitado. Remover/rebaixar o ator impede novos batches apply. Referência ao ator é lógica e nullable, sem FK que impeça exclusão.

## Evidência e contagens

O início fixa máximo de `EmailEvent.id` da conta via recipient→campaign→account e máximo de `EmailSuppression.id` legado da conta. Sem janela de datas: todo histórico disponível até esses limites é elegível, inclusive evidência antiga. Inserções posteriores são ignoradas. IDs não são um snapshot transacional: alterações/exclusões concorrentes em linhas antigas podem afetar o que será lido. Event/recipient/campaign devem manter o vínculo histórico de tenant; há checagem adicional de conta ao construir prova.

- Bounce usa o `BounceClassifier` final, separando classificação da entrega e origem do bloqueio. `Permanent/General` e `Permanent/NoEmail` produzem `hard_bounce`, com `reason_code=permanent_failure`; **NoEmail não significa caixa inexistente**, e sim endereço não extraído da devolução.
- `Permanent/Suppressed` global é evento permanente prejudicial à métrica de bounce, mas o bloqueio tem origem **provider_suppression**, nunca hard-invalid. `OnAccountSuppressionList`, `OnTenantSuppressionList` e `EmailValidationSuppressed` são prevenção pelo provedor, sem tentativa; classificação `unknown`, bloqueio `provider_suppression`. Todos produzem bloqueio local durável, sem expiração, espelhado no legado.
- `UnsubscribedRecipient` produz `unsubscribe`, mesmo dentro de um evento bounce; classificação `unknown`, opt-out sem tentativa. Mantém a chave SNS `ses:<messageId>:bounce`. Não cria/reescreve eventos unsubscribe, status ou contadores de campanha no backfill. Status de destinatário sozinho ou payload vazio não prova permanência.
- Complaint e unsubscribe usam seus eventos persistidos. Transient é ignorado: replay histórico nunca fabrica três soft bounces para quarentena. Demais eventos apenas avançam o cursor.
- Chaves ao vivo preservadas: `ses:<messageId>:bounce`, `ses:<messageId>:complaint`, `unsubscribe:<recipient_id>`. Para SES usa `mail.messageId`, ou o identificador do destinatário; sem chave utilizável, `historical:email_event:<id>` dá dedupe durável da linha, sem prometer dedupe de uma notificação futura cujo identificador era desconhecido.
- Legado usa `historical:email_suppression:<id>`. Razão forte conhecida é mantida, inclusive `provider_suppression` (não convertida em manual). Razão arbitrária vira prova limitada `legacy_permanent_positive`, com `manual` no novo registry. Texto antigo continua intacto na tabela legada, sem copiá-lo para metadados/logs. `occurred_at` recebe `created_at` original; a data do positivo legado não é reescrita. Estado mais forte nunca é rebaixado; novas provas mais fortes podem promover razões conhecidas pelo contrato do registry.
- Toda aplicação passa por `SuppressionRegistry.block!`, `source: backfill`. Metadados têm allowlist: `historical_event_id` ou `legacy_suppression_id`, `maintenance_run_id`, classificação/`reason_code` produzidos pelo classificador, ou `evidence_code=legacy_permanent_positive`. Não copiam payload, endereço, chave SES ou motivo livre do operador. O motivo fica somente no run privado; não é devolvido nem logado por esta manutenção. Não existe outro depósito de quarentena.

| Contador | Unidade e significado |
| --- | --- |
| `events_processed` | Linhas de evento consumidas, incluindo ignoradas. |
| `eligible_events` | Eventos que sustentam bloqueio durável, inclusive prevenção pelo provedor e opt-out; não é contador de tentativas nem numerador de reputação. |
| `already_protected_events` / `unprotected_candidate_events` | Eventos cujo endereço estava protegido/não protegido na consulta imediatamente anterior ao registry. São observações por evento, não endereços únicos nem contagem atômica de transições sob escritores concorrentes. No preview, eventos repetidos podem contar como candidatos repetidos. |
| `block_records_created` / `duplicate_events` | Registros de bloqueio realmente acrescentados pelo registry / chaves de evento já existentes. Novo registro de auditoria não significa endereço recém-bloqueado. |
| `skipped_unknown_events` / `skipped_temporary_events` / `skipped_other_events` | Eventos ignorados por classificação. |
| `legacy_rows_processed` | Positivos legados examinados; em dry_run somente observados. |
| `legacy_rows_mirrored` / `duplicate_legacy_rows` | Provas legadas realmente acrescentadas / já registradas. |

Não somar contagens de runs como se fossem pessoas ou endereços únicos. Provas simultâneas do caminho ao vivo podem alterar a observação de proteção; o resultado `duplicate` do registry é a autoridade para dedupe. As supressões fortes são espelhadas no contrato positivo legado e continuam eficazes com leitores antigos após rollback.

## Progresso, falhas e recuperação

Cada job processa no máximo o batch solicitado (até 500 linhas) e cede após orçamento de dez segundos entre linhas. Latência de uma consulta/transação em andamento não é limitada por esse orçamento. Não há transação de lote inteiro: cada linha grava registry + contador + cursor atomicamente sob lock do run. Perder o processo conserva linhas já concluídas; uma transação interrompida reverte prova e cursor juntos.

Lease dura dois minutos, renovado a cada linha, com token conferido sob lock. Workers duplicados não compartilham lease; um holder antigo não grava depois de um reclaim. Tentativas por batch: no máximo três; contador zera ao finalizar um batch. Falhas repetidas ou três leases perdidos levam a `failed`. Progresso persistido inclui `attempts`, `enqueue_attempts`, `error_count`, código limitado, timestamps/lease e tempo decorrido.

O run é outbox durável. `after_save_commit`, filtrado por estado pending e prazo de dispatch vencido, solicita o primeiro job, a continuação e o retry somente após o commit externo; rollback não publica trabalho. O filtro usa estado/prazo persistidos, não dirty tracking que um reload pode apagar antes do commit; a reserva futura impede republicação recursiva. O reconciliador cobre interrupção após commit e antes do callback/publicação; falha de enqueue deixa o run existente. Nova reserva somente após cinco minutos, até três enqueues sem claim; o quarto ciclo marca `enqueue_exhausted`. Reconciliação também recupera mensagem perdida e lease expirado. Falha de publicação não apaga run ou supressão. GET e repetição do POST original não reabrem execução terminal.

Para `failed`, corrigir a causa e usar `POST .../maintenance/backfills/:id/retry` com body vazio, pelo **mesmo ator original ainda SuperAdmin**. Preserva chave, motivo, modo, horizontes, cursores, provas e erro acumulado; zera orçamento de tentativas. Run ativo/concluído retorna 422 `run_not_failed`. Outro ator retorna 422 `actor_mismatch`; se o ator foi removido, outro SuperAdmin pode criar um novo run explícito com nova chave, aproveitando dedupe do registry. Código genérico de falha é `batch_failed`, nunca texto de exceção; configuração inválida vira `invalid_configuration`. Logs próprios usam `email_protection.*` e somente campos públicos, sem e-mail, payload, token, motivo ou chave de idempotência.

FK da nova tabela de runs para account é `ON DELETE CASCADE`; não impede exclusão autorizada da conta. Um job cujo run foi removido não faz retry. A migration de higiene inspecionada remove estados por cascade da conta e mantém auditoria com referências numéricas lógicas, sem FK restritiva para account/state. Esta migration de manutenção não altera retenção do legado nem o processo existente de exclusão/cleanup. O teste de limpeza usa uma observação sem positivo legado para verificar que a nova auditoria não impede account.destroy!.

### Erros e escopos exatos

| Superfície | Resposta/contrato |
| --- | --- |
| create/retry inválido | 422: `unsupported_parameter`, `invalid_mode`, `invalid_reason`, `invalid_idempotency_key`, `invalid_batch_size`, `idempotency_conflict`, `apply_disabled`, `run_not_failed`, `actor_mismatch`, conforme operação. |
| Flag malformado no request | 422 `invalid_backfill_configuration`; no worker vira erro persistido `invalid_configuration`. |
| Worker | `batch_failed` redigido (sem mensagem original), `actor_unavailable`, `apply_disabled`, `attempts_exhausted`. |
| Publicação/reconciliação | `enqueue_failed`, `enqueue_exhausted`; run continua durável. |
| Auth/Pundit | 401 sem usuário, sem associação à conta ou sem SuperAdmin; conta suspensa também usa middleware existente. API por token pode retornar 403 se o plano bloquear API. Feature indisponível e run ausente/estrangeiro: 404. |

Create/show aceitam SuperAdmin persistido com associação à conta da URL; retry exige também o ator original. Serviços internos Start/Retry verificam SuperAdmin, mas não associação: a fronteira HTTP aplica o acesso à conta. Start reaproveita a chave por conta; outro SuperAdmin autorizado pode ler o run original, mas não assumir seu retry. Não há capability de unlock, reset de reputação, mudança de domínio, retomada ou override nesta API. O payload público é allowlist de progresso; não inclui ator, motivo, chave de idempotência, token de lease, dados do provedor ou mensagens arbitrárias.

## Observabilidade e pré-condições do provedor

Monitorar fila `housekeeping`, idade de `next_dispatch_at`, leases vencidos, ausência de avanço dos cursores, `error_count`, códigos terminais e duração. Alertar antes de exaurir três tentativas; verificar bloqueios/pausas existentes antes e depois do apply. Progresso sem dados não significa reputação boa.

**Métricas locais versus oficiais:** `EmailCampaigns::Reports::Metrics` deriva taxas dos eventos e destinatários locais (`sent_at`), no conjunto selecionado de campanhas SES, e publica `official_ses_ratio=false`. O denominador oficial AWS, sua janela e escopo não são comprovados pelo backfill. Um bounce `Suppressed` permanece no histórico como permanente, com origem provider_suppression; as três prevenções sem tentativa e opt-out não devem ser convertidos em hard bounce. Contagens desta manutenção são provas processadas, não métricas AWS, domínios saudáveis ou endereços únicos. A semântica do provedor segue o contrato de higiene fornecido pelo parent e [hygiene.md](hygiene.md); nenhuma fonte externa foi consultada nesta revisão sem rede.

**Pendência concreta do parent em reports:** na leitura desta rodada, `Reports::Metrics#load_bounces` incrementa `provider_prevented` para todo `reason_code=provider_suppression`, incluindo global `Suppressed`. Isso conflita com a definição de prevenção sem tentativa; corrigir/verificar no workstream de reports. Não excluir `Suppressed` do numerador permanente para corrigir esse contador. A manutenção não altera nenhum desses contadores.

O workstream B é a autoridade para telemetria de SES/CloudWatch, limites, alarmes e IAM. Antes de ativar seu monitor, o integrador deve anexar sua documentação/policy de menor privilégio, confirmar conta/região/configuration set e somente permissões de leitura que os métodos realmente usados exigem. Conferir leitura de métricas CloudWatch e estado/quota de envio SES segundo esse contrato; não conceder escrita de supressão, habilitação de envio ou alteração de alarmes por conveniência. Falta/atraso de telemetria é desconhecido, não saudável. Nenhuma métrica/alerta AWS foi simulada ou consultada aqui.

Configurar e validar alertas antes da zona insegura definida por B e pelo provedor; não usar limites de pausa como meta aceitável. Não há número universal de segurança derivado deste backfill. Parâmetros e ações IAM exatos de B precisam estar anexados pelo integrador antes de aprovar monitor/rollout; ainda não estavam disponíveis neste worktree na inspeção.

Preflight DNS novo verifica apenas rota/configuração de domínio dentro de suas limitações. Não garante caixa válida, entrega, consentimento ou reputação. Não faz SMTP probing. Nenhum controle recolhe mensagens já aceitas/em voo.

## Rollback / versões mistas / retenção

Desabilitar apply e novas solicitações operacionais, pausar a agenda opt-in e drenar jobs desta manutenção antes de remover suas classes por rollback de código. A mudança de configuração e o rollback exigem aprovação. Jobs antigos enfileirados com classe ausente precisam do procedimento de filas aprovado do integrador; não executar purge indiscriminado. A outbox preservada permite recuperação após reupgrade/reconciliação explícita.

Rollback comportamental: higiene em shadow, DNS=false, novo monitor desligado, backfill flag=false. Preservar proteções existentes, pausas manuais, pausa do tenant, bloqueio do provedor/SES e breaker global. Este fluxo nunca libera conta, altera quota/provedor ou reenvia mensagens.

Rollback de código retém tabelas, positivos permanentes, estados e histórico completo de auditoria/runs. **Não rodar down, apagar auditoria/supressão, resetar cursores ou limpar razões fortes.** A migration é irreversível por design e não faz backfill automático. Leitores antigos continuam vendo positivos fortes em `EmailSuppression`; enforcement temporário pode ficar indisponível em versão antiga, conforme o contrato de higiene. Voltar versão não revoga opt-out/spam/hard bounce. Não há expiração/purge de histórico neste pacote; exclusão autorizada de conta segue seu processo próprio.

## APIs internas para integração

- `Maintenance::Start.call(account:, actor:, parameters:, config: Maintenance::Config.new)` → run idempotente; único ponto operacional de criação.
- `Maintenance::HistoricalProtectionBackfill.new(run:, config: nil).call` → consome no máximo um batch, persiste progresso e agenda continuação. Config injetada é exclusivamente conveniência de testes locais; execução normal lê o flag real por batch.
- `Maintenance::Dispatch.call(run_id)` → reserva/publica trabalho existente, sem criar runs.
- `Maintenance::Retry.call(run:, actor:, config: Maintenance::Config.new)` → reinicia orçamento de um run failed do ator original.
- `EmailCampaigns::ProtectionBackfillJob.perform_later(run_id)` / `ProtectionBackfillReconcileJob` → fila `housekeeping`; operador usa API, não invocação Rails em produção.
- `EmailProtectionMaintenanceRun#public_progress` → representação limitada, sem dados pessoais ou provedor.

Validação realmente executada e limitações estão em [436-operations](../audit/436-operations.md). RSpec/Rails/banco não foram executados aqui. O integrador deve testar também a preservação de trigger_snapshot, histórico, breaker global/modelos finais de B. Na inspeção desta rodada havia consumidores Presentation desses contratos, mas não os modelos/serviços finais de Reputation/Provider neste worktree. Não substituir essa lacuna por mocks e alegar conclusão operacional.


## Sequência segura por PR para o parent

1. **PR0/higiene:** review da matriz final de subtipos, supressão antiga/nova, retenção e migrations `20260916120000`/`20260916120100`; executar testes puros e Rails isolados do código final. Schema é responsabilidade do parent. Preparar rollback de código mantendo tabelas/positivos. Aprovação explícita antes do merge que dispara deploy; aguardar as duas stacks e smoke autorizado.
2. **PR1/reputação/provedor:** só após PR0 estável, integrar modelos reais, IAM/configuração e preservar trigger/histórico e travas. Testar denominador local versus oficial e prevenções sem tentativa; monitor inicia desligado. Mesmo ciclo review → aprovação → merge/deploy → observação independente, com rollback que não limpa triggers/travas.
3. **PR de reports/UI:** alinhar a matriz global Suppressed versus prevenções, corrigir a pendência acima e validar atores, capabilities e erros contra backend real. Aprovação e observação do deploy antes da próxima PR; nenhum contador local autoriza desbloqueio.
4. **PR de manutenção:** conectar apenas as três rotas descritas, a documentação da flag `EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED=false` no arquivo de exemplo, migration `20260916123000` e testes. Nenhuma modificação de routes/schedule/env/schema foi feita nesta revisão. A agenda do reconciliador fica opt-in; o parent define seu gate sem inventar novo nome de env aqui. Review e aprovação antecedem merge/deploy, com apply desligado.
5. **Operação posterior separadamente aprovada:** habilitar reconciliação opt-in para garantir recuperação de previews existentes; criar preview explícito por conta e acompanhar estado, horizonte, cursores, erros e contagens. Repetir preview se vazio/falhou ou se evidência/horizonte relevante mudou. Aprovar configuração/apply separadamente; então nova chave e `mode=apply`, com acompanhamento e reconciliação até terminal. Conferir proteção, pausas e histórico depois, sem tentar enviar mensagens reais como parte do backfill. Não há autorização de merge, deploy ou apply nesta entrega.

As quatro PRs são uma sequência lógica de dependências, não declaração de PRs abertas ou integradas. Não agrupar merges automáticos antes de observar cada deploy. A manutenção exige histórico de supressão preservado no rollback, nunca reversão destrutiva de migration.
