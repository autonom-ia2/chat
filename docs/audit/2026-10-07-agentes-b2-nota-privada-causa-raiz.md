# B2-TEC-01 — nota privada não é resposta errada

**Data:** 2026-10-07
**Estado:** causa raiz registrada antes do RED; nenhuma correção de produto aplicada.

## Contrato

Uma nota privada é uma anotação interna da conversa. Ela não pode ser marcada como
resposta errada do agente, somada às métricas de respostas erradas, exibida no
drawer de analytics nem oferecer a ação “Reportar resposta” no menu da mensagem.
Uma mensagem pública de saída do espelho AgentBot, identificada por
`autonomia_agent_id`, continua elegível. O comportamento que conta uma resposta
publicada mesmo quando o agente ficou silencioso continua preservado.

## Evidência no código

- `app/controllers/api/v1/accounts/autonomia/agents/message_reports_controller.rb:37-42`
  aceita a mensagem quando `sender_type == 'AgentBot'` e
  `content_attributes['autonomia_agent_id']` existe, sem excluir
  `private: true`.
- `app/services/autonomia/agents/analytics.rb:232-235` restringe os reports por
  conta, janela, conversa atendida e `messages.sender_type = 'AgentBot'`, mas
  não restringe `messages.private = false`.
- `app/javascript/dashboard/components-next/message/Message.vue:193-197` define
  `isAutonomiaAgentMessage` somente por saída e `autonomiaAgentId`; em
  `:426-430`, `reportAgent` usa esse resultado e o estado de exclusão, sem
  considerar `private`.

## Causa raiz

A fronteira de privacidade foi deixada implícita em cada camada. O remetente e o
carimbo provam a origem do AgentBot, mas não provam que a mensagem é uma resposta
pública. Como o predicado `private = false` não é aplicado na entrada, no leitor
de métricas e na affordance da UI, a mesma nota privada pode ser criada como
report, contada e oferecida para reporte.

## RED planejado

As specs devem provar, sem alterar o produto nesta etapa:

1. POST de uma nota privada com o mesmo carimbo retorna `422`, mantém o erro
   existente (`Only Autonomia agent messages can be reported`) e não cria
   `Captain::MessageReport`;
2. analytics não conta nem retorna no escopo uma nota privada reportada;
3. o drawer Enterprise não devolve linha para esse report;
4. o menu de uma mensagem privada não expõe `reportAgent`, enquanto uma mensagem
   pública elegível mantém a ação.

O registro da causa e a preparação das specs não executaram RSpec, testes
JavaScript, banco, serviços, produção, commit, push ou merge. A correção fica
limitada ao controller, analytics e menu Vue, preservando as demais permissões e
o fluxo de nota privada.

## Resultado do RED22 antes da correção

O snapshot `20261007-182755-532a5b7b-17fe0961a1-fd384075` foi executado no M2
com o job `m2-cf82527fb63945769c6ae38c0f6f5013`; o relatório Ruby é
`/tmp/chat2you-agentes-b2-b3-red22.json` e o SHA informado foi
`c31bf81db0867e25bd4dc2c3e78f4a45e4f738a691b3f5d6bb90012c6a53b1bb`.

Resultado: 222 exemplos, 8 falhas, 0 pendentes e 0 externos. As três provas
deste bloco falharam exatamente na causa registrada: o POST criou report para a
nota privada, o Analytics contou 1 resposta errada e o drawer devolveu 1 linha.
O RED JavaScript ainda estava bloqueado pela preparação de dependências no M2;
nenhuma correção de frontend foi aplicada neste bloco.

## Resultado do RED JavaScript antes da correção

O snapshot `20261007-182755-532a5b7b-17fe0961a1-fd384075` foi executado no M2
com o job `m2-3bf3eb66bb3d4f8ab5deca6fe59ab969`; o relatório é
`/tmp/chat2you-agentes-frontend-red22.json` e o SHA informado foi
`05318f55650d30ac32a919ab9146eba7d625c130b0aa1ac29af945a33f3e85a4`.

Resultado: 38 execuções, 29 pass, 9 falhas e 4 casos F0 sem coleta. A prova
`Message.spec.js:66` confirmou que uma mensagem privada ainda expunha
`enabledOptions.reportAgent=true`, enquanto a mensagem pública elegível mantinha
a ação. A causa ficou confirmada antes da alteração única no predicado de
`Message.vue`; não houve teste, banco, serviço, produção, commit, push ou merge
depois deste recibo.
