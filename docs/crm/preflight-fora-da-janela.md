# Pré-voo do follow-up fora da janela de 24 h (#1624, épico #1585)

## O que faz
Dez minutos antes de um follow-up automático sair no WhatsApp oficial, quando a janela de 24 h **no horário do envio** já
estará fechada, o sistema decide o que o envio vai usar e, se faltar, cria o modelo (com a autorização da conta), para a Meta
ter tempo de aprovar antes de `due_at`.

- **Cobrança** (`service_reminder`, `payment_*`): planeja o tipo `cobranca_antes|no_dia|depois` no ponto único
  (`Whatsapp::Templates::EnvioForaDaJanela`), criando o modelo quando a conta autorizou e ele não existe.
- **Retorno combinado** (`ai_callback`): a IA compõe uma vez, escolhendo entre os modelos aprovados. Se nenhum serve
  (`no_fitting_template`), planeja o tipo `retorno` com `ja_recusado: true`. No horário o runner reusa a composição
  (sem 2ª chamada paga) se ela tem até 15 min, a lista de modelos é a mesma e não houve tentativa anterior falhada.

## Peças
- `Crm::FollowUpPreflightJob` (cron de 1 min, fila `scheduled_jobs`) só enfileira, um job por follow-up.
- `Crm::FollowUpPreflightRunJob` (fila `low`) chama `Crm::FollowUps::Preflight`.
- Marca em `crm_follow_ups.metadata['preflight']`: `{estado: iniciado|pronto|erro, due_at, at, tipo, plano, composicao, candidatos}`.
  Chave do servidor (`MetadataSanitizer::SERVER_OWNED_KEYS`): o cliente não grava nem apaga. Vale só para o `due_at` gravado.
- `Crm::FollowUps::EnvioForaDaJanela` é o elo com o ponto único: usa o plano gravado ou planeja **sem criar** (criar é do pré-voo).
- Depois do `:sent`, o runner chama `registrar_envio` (tabela `whatsapp_out_of_window_sends`).

## Como o envio se comporta sem o pré-voo
Igual a hoje: planeja sem criar, usa o modelo já aprovado, senão Híbrido (retorno) ou aviso à equipe. Pré-voo com erro grava
`estado: erro` e não repete a chamada paga. O motivo do aviso agora vem do ponto único (`em_analise`, `no_template`, ...), com
o mesmo texto de `crm.service_reminders.aviso.*`.

## Observar
Marca de um follow-up: `Crm::FollowUp.find(ID).metadata['preflight']`. Registros: `WhatsappOutOfWindowSend` por `crm_follow_up_id`.
Log: `[crm][preflight]` (aviso em erro).

## Desligar / rollback
Remover a entrada `crm_follow_up_preflight_job` de `config/schedule.yml` (ou desligar `CRM_AI_ENABLED`): o envio segue sem pré-voo.
Reverter o PR devolve o `Crm::FollowUps::EnvioForaDaJanela` ao Garantir direto. Nada de migration.
