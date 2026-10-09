# Reputação e proteção de campanhas de e-mail

Atualizado em 2026-09-29 pela #765. Este documento descreve o comportamento vigente.
A lógica anterior em que a reputação local de um tenant criava um latch persistente de
bloqueio foi aposentada. Documentos de auditoria anteriores continuam históricos, mas
não definem mais o comportamento operacional.

## Responsabilidades

A proteção de campanhas tem três camadas independentes:

1. **Higiene por destinatário**: hard bounce, complaint/spam, opt-out, supressões e
   preflight continuam impedindo novos envios para o endereço afetado.
2. **Métricas locais por conta**: a coorte local de sete dias continua calculada para
   diagnóstico, alertas, relatórios e auditoria. Ela não decide admissão de envio.
3. **Saúde global de envio**: a telemetria oficial do provedor é a única autoridade
   reputacional que pode interromper novas admissões do canal em massa.

DirectInbox não usa o gate global do canal em massa. Continua sujeito à higiene e às
regras próprias de elegibilidade da campanha.
## Métricas locais

`EmailCampaigns::Reputation::Metrics` conta destinatários com aceite confirmado
(`sent_at`) dentro da janela de sete dias e classifica permanent, transient, unknown,
complaints e provider_prevented.

`Policy` continua produzindo níveis de diagnóstico:
- permanentes >= 2%: warning;
- permanentes >= 4%: high_risk;
- permanentes >= 5% com pelo menos cinco: policy_pause=true;
- qualquer complaint: spam_alert=true;
- complaints >= 0,05%: attention;
- complaints >= 0,1%: policy_pause=true.

Esses limiares **não pausam a conta**. O evaluator publica `policy_pause` para
diagnóstico, mas força `pause=false`, `blocked=false` e `resume_allowed=true`.
Um nível local que a Policy chamaria de `paused` é apresentado como `high_risk`.

Observações superseded não publicam métricas antigas e não criam bloqueio. Elas apenas
solicitam nova avaliação pela fila.
## Supressão e complaints

A classificação de destinatários permanece conservadora e independente do guardrail
global.

- Permanent bounce real permanece evidência de falha de entrega.
- Transient e unknown permanecem separados.
- Complaint real bloqueia o destinatário.
- Unsubscribe/opt-out bloqueia o destinatário.
- `OnAccountSuppressionList`, `OnTenantSuppressionList`,
  `EmailValidationSuppressed` e `UnsubscribedRecipient` são prevenções e não devem
  ser reinterpretadas como uma nova reclamação ou mailbox inexistente.

Eventos brutos e auditoria são preservados. A #765 não apaga histórico e não relaxa
supressões individuais.
## Gate global de saúde de envio

`ProviderMonitor` coleta, fora do caminho de admissão:
- estado atual da conta de envio (`SendingEnabled` e `EnforcementStatus`);
- `Reputation.BounceRate`;
- `Reputation.ComplaintRate`.

O monitor roda a cada cinco minutos quando
`EMAIL_REPUTATION_PROVIDER_MONITOR=true`.

Defaults preventivos:
- bloqueio por bounce >= 5%;
- bloqueio por complaint >= 0,1%;
- `PROBATION`, `SHUTDOWN` ou envio desabilitado bloqueiam;
- telemetria ausente/antiga segue `EMAIL_REPUTATION_PROVIDER_UNKNOWN_ACTION`
  (default: block).

O gate é global para a conta/região configurada e não depende do tenant que originou
os eventos.
## Recuperação automática e histerese

Um bloqueio global não exige volume local de recuperação nem override de tenant.

Defaults de recuperação:
- bounce < 4%;
- complaint < 0,08%;
- duas observações frescas e consecutivas abaixo dessas faixas.

Variáveis:
- `EMAIL_REPUTATION_PROVIDER_BOUNCE_RECOVERY_RATIO=0.04`
- `EMAIL_REPUTATION_PROVIDER_COMPLAINT_RECOVERY_RATIO=0.0008`
- `EMAIL_REPUTATION_PROVIDER_RECOVERY_OBSERVATIONS=2`

A observação precisa avançar no tempo. Erro/unknown ou valor dentro da banda de
histerese zera a sequência. Um `manual_block` operacional nunca é removido pela
recuperação automática.

Polls concorrentes são monotônicos: uma observação nociva antiga que termina depois
de uma saudável mais nova pode adicionar o latch e incrementar
`harmful_generation`, mas não pode rebaixar `status/telemetry/checked_at` mais novos.
## Retomada de campanhas

Quando o gate global abre novamente, `ProviderRecoveryJob` tenta retomar somente
campanhas pausadas explicitamente com:
- `pause_reason.kind=provider`; e
- código `provider_blocked` ou `provider_telemetry_unknown`.

Pausa manual, higiene, import ativo e qualquer outra causa não são retomadas
automaticamente. `EmailCampaign#resume!` revalida higiene/import e o gate global no
momento da retomada.

O job recebe `provider_key` e `harmful_generation`; jobs de recuperação de uma
geração antiga são ignorados.
## Aposentadoria do bloqueio local legado

Estados antigos com `EmailReputationState.blocked=true`, override local ou a flag
`account.internal_attributes.email_campaigns_paused` deixam de ser autoridade de
admissão.

Ao serem avaliados, esses estados são reconciliados:
- `blocked=false`;
- override local limpo;
- flag legada removida de forma atômica, preservando outras chaves JSON;
- auditoria `tenant_protection_retired`;
- snapshot histórico do incidente permanece imutável.

`TenantProtectionRetirementJob` reconcilia campanhas antigas pausadas pela reputação
local. Ele aceita o formato estruturado de pausa reputacional e o marcador textual
legado conhecido no `last_error`. Nenhuma pausa manual ou erro não reconhecido é
retomado por esse job.
## Override e release manual

O override de reputação por tenant foi aposentado. A rota antiga continua protegida
por autorização para compatibilidade, mas SuperAdmin recebe
`email_campaign.invalid_override`; não é criado novo override.

`ProviderRelease` permanece disponível para SuperAdmin como fallback operacional de
emergência/manual. O fluxo normal do bloqueio global é recuperação automática por
histerese. Um manual block continua exigindo ação operacional explícita.

Nenhuma dessas operações limpa supressões de destinatários ou histórico de auditoria.
## Contrato público e UI

A UI deve ser discreta e não expor nomes de infraestrutura/provedor. Usar termos como:
- **Saúde de envio**;
- **Reputação do domínio**;
- **Problemas da campanha**;
- **Envio temporariamente protegido**.

Métricas locais podem aparecer como atenção/risco elevado, nunca como prova de bloqueio
da conta. O provider DTO público continua limitado a `state` e `observed_at`; IDs de
conta, razões privadas, telemetry bruta e detalhes operacionais não são serializados.

`capabilities.override` permanece no formato público por compatibilidade, sempre
`false`.
## Concorrência e ordem de locks

Claims SES preservam a ordem:
`Account -> EmailReputationState -> EmailProviderState -> Campaign -> Recipient`.

A avaliação local coleta métricas fora de locks longos. O monitor global coleta rede
antes do lock do provider. Renderização e envio externo nunca ocorrem dentro desses
locks.

`DeliveryClaim` não consome mais orçamento de override local, porque esse mecanismo
foi aposentado. A proteção individual e o gate global continuam sendo consultados no
caminho final de admissão.
## Rollout e rollback

Antes do deploy:
1. testes de reputação/admissão/concorrência e requests devem estar verdes;
2. validar as variáveis novas de histerese;
3. confirmar que o monitor global está configurado quando o ambiente deve usar o gate;
4. não remover tabelas, triggers, auditorias ou snapshots antigos.

Rollback de aplicação deve preservar todo o estado e histórico. Não executar limpeza
de banco para “liberar” envio.

A #765 não exige migração de schema.
