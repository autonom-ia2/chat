# Opt-out do follow-up de IA decidido pelo modelo (#1317)

## Contexto

`Crm::FollowUps::AutoFollowupCanceler` decidia se a resposta do cliente era pedido para parar ("SAIR" e afins) com duas listas de palavras e regex de normalização. A regra do Rodrigo de 20/09/2026 proíbe interpretar o que uma pessoa escreveu com lista de palavras ou regex. Recusa escrita fora da lista passava como resposta comum, e o card voltava a ser elegível para a cadência.

## Decisões

- **Parar a cadência não depende de IA.** Qualquer resposta inbound cancela os toques `ai_followup` na hora, como antes. O canceler não lê mais o texto.
- **O rótulo de opt-out vem do modelo, num job.** `Crm::FollowUps::OptOutDecisionJob` → `Crm::Ai::OptOutClassifier`, reaproveitando o que o CRM já usa: `CredentialResolver` (chave da conta) e `ResponsesClient` com `json_schema` estrito. Feature `follow_up_saida` na Gestão IA, em "Lembretes de retorno".
- **Saída:** `pediu_para_parar` ∈ `sim` | `nao` | `nao_se_aplica` e `motivo` em códigos fechados. Sem texto livre: o log nunca leva conteúdo da conversa.
- **Contexto do modelo:** a resposta e a última mensagem pública enviada ao cliente. Nota privada do time fica de fora.
- **Fail closed.** Enquanto a decisão está `pendente` ou falhou (`falhou`, `sem_credencial`, `ai_disabled`), o planner não re-arma o card. Libera com `nao`/`nao_se_aplica` ou com o RESET manual do drawer. Card anterior a esta mudança (sem a chave) segue a regra antiga.
- **Falha explícita.** Erro do provedor ou resposta fora do schema: `retry_on`, 5 tentativas com espera crescente; esgotado, grava `opt_out_decision: falhou` e loga `[crm][ai][opt_out] ... erro=<classe>`. Sem chave de IA: `discard_on`, grava `sem_credencial`. Nenhum `rescue` genérico. Só a classe do erro vai ao log, porque a mensagem do provedor pode ecoar o input.
- **Decisão velha não sobrescreve.** O job só grava se o estado ainda é o daquela parada (`stopped_message_id` + `pendente`), conferido de novo dentro do `with_lock`.
- **Timeline:** um SAIR gera duas atividades `ai_followup_stopped` — `replied` na hora e `opt_out` quando o modelo decide.
- **Na dúvida, `nao`.** Mesma escolha da lista anterior: um `sim` errado marca como recusa quem não recusou.

## Fora deste PR

- Só a resposta que para a cadência é avaliada. Um SAIR enviado depois de outra resposta, com a cadência já parada, não é classificado. O comportamento é o mesmo de antes, porque a lista também só rodava com a cadência ativa. Vai em issue própria.

## Validação local (M2, snapshot do MacCluster; swap do M4 acima de 28 GB)

- RSpec: `spec/services/crm/follow_ups/`, `spec/jobs/crm/follow_ups/`, `auto_followup_reset_flow_spec`, `spec/services/crm/reports/` e `card_syncer_spec`. Resultado: 196 exemplos, 0 falhas e 3 pendentes. As 3 pendências são de quarentena antiga (`QUARANTINE: pre-existing legacy failure`).
- RuboCop nos 10 arquivos tocados: sem ocorrências.
- Revisão independente (`caveman:cavecrew-reviewer`): 2 graves e 6 riscos.
  - Corrigidos: fail open do planner quando a decisão falha; nota privada no contexto; `error.message` no log; esforço de raciocínio fora da convenção de `Crm::Ai::Config`.
  - Recusados com motivo: o risco de transação não se aplica, porque o canceler roda fora do `SyncLock`, dentro do `SyncConversationCardJob`. As duas atividades na timeline foram mantidas.
  - Pré-existente, em issue própria: SAIR enviado depois da primeira resposta.
