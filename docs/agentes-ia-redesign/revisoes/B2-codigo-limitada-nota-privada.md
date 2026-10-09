# Checagem limitada B2 — nota privada

**Data:** 2026-10-07  
**Alvo congelado:** snapshot23 em `/Users/Shared/maccluster-workspaces/chat2you/20261007-184308-532a5b7b-9803329751-205ae53c/src`  
**SHA do alvo:** `9803329751ae3fce6fd8cec442e77faa9170b38434587aac62a8e81438e480ad`

## Escopo

Checagem independente e limitada somente do achado B2-TEC-01, sobre a nota privada
do agente. Não reabri a revisão normal B2, não executei testes, build, banco,
serviços ou produção e não alterei o produto.

## Resultado

**PASS limitado no alvo estático, sem residual concreto.** A correção fecha as três
fronteiras independentes do achado. Isto não antecipa o resultado do test23 que
estava em execução; RED22 continua sendo a evidência anterior à correção.

## Evidência

1. **Entrada sem escrita:**
   `app/controllers/api/v1/accounts/autonomia/agents/message_reports_controller.rb:6-18,37-43`
   executa `ensure_autonomia_agent_message` antes de `create` e só deixa passar
   AgentBot público com `autonomia_agent_id`. Uma nota privada recebe o erro
   existente `Only Autonomia agent messages can be reported`, com `422`, antes de
   `Captain::MessageReport.create!`.

2. **Leitura histórica e contagem:**
   `app/services/autonomia/agents/analytics.rb:232-244` aplica
   `messages: { sender_type: 'AgentBot', private: false, ... }`. Reports antigos
   de notas privadas ficam fora de `wrong_replies`, de `wrong_reply_report_scope`
   e, por consequência, de `reported_conversations`.

3. **Drawer Enterprise:**
   `app/controllers/api/v1/accounts/autonomia/agents/analytics_controller.rb:39-50`
   usa a mesma relação já filtrada pelo Analytics; em seguida aplica a visibilidade
   da conversa antes de ordenar, limitar e serializar. Não há uma consulta paralela
   que reintroduza mensagens privadas. A spec correspondente prova o caso em
   `spec/enterprise/requests/api/v1/accounts/autonomia/agents/analytics_wrong_replies_spec.rb:101-118`.

4. **Menu da mensagem:**
   `app/javascript/dashboard/components-next/message/Message.vue:426-433`
   exige `!props.private` para `enabledOptions.reportAgent`. A mensagem pública
   elegível continua habilitando a ação; a cobertura está em
   `app/javascript/dashboard/components-next/message/specs/Message.spec.js:61-74`.

5. **Regressão preservada:**
   `spec/services/autonomia/agents/analytics_spec.rb:140-173` mantém o caso de
   uma resposta pública do espelho contar mesmo quando o agente ficou silencioso,
   e separa dele o caso de nota privada, que deve resultar em zero.

## Limite da conclusão

Não declarei CI ou GREEN: a execução test23 ainda é a validação dinâmica pendente.
Se ela falhar fora das expectativas já registradas, a causa deve ser reaberta antes
de qualquer aprovação; a leitura deste snapshot não encontrou motivo para STOP.

