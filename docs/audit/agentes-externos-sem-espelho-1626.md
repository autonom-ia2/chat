# #1626 — Agentes externos sem os espelhos dos agentes da plataforma

## Decisão

- Prepend `Autonomia::Agents::RobosSemEspelho` em `Api::V1::Accounts::AgentBotsController`
  (`config/initializers/autonomia_robos_sem_espelho.rb`). O controller do core e o enterprise ficam intactos
  (não há override de agent_bots em `enterprise/`).
- `index`: tira os ids de `autonomia_agent_inboxes.agent_bot_id` por subquery, inclusive de vínculo apagado
  logicamente (o espelho segue autor das mensagens antigas).
- Ações por id (`show`, `update`, `destroy`, `avatar`, `reset_access_token`, `reset_secret`): 404 para espelho,
  pelo `before_action :agent_bot`.
- O Agentes IA cria e apaga espelhos por dentro (`Operate::InboxConnector`, `Areas`, `SoftDelete`, `AgentInbox`),
  sem chamar esta API; conferido por grep.

## Efeito colateral conhecido

- Atualizado no #1648: a aba da caixa virou "Agente de IA" (`AbaAgenteDeIa.vue`, componente do fork; o
  `BotConfiguration.vue` do Chatwoot ficou intacto e fora da tela). Ela não lê mais a lista de robôs: lê e troca pelo
  `GET/PUT autonomia/inboxes/:inbox_id/quem_atende`, cujas opções também deixam os espelhos de fora
  (`AgentInbox.espelhos`) e os robôs de sistema (sem conta; conferido em produção em 15/10, nenhuma caixa usa).
- A rota crua `inboxes/:id/set_agent_bot` ganhou o prepend `CaixaSemAgenteExterno` no #1648: recusa agente de outro
  sistema em caixa com porta da plataforma e recusa espelho de agente da plataforma que não é a porta da caixa.

## Validação

- Spec novo `spec/requests/api/v1/accounts/autonomia/agents/robos_sem_espelho_spec.rb`: vermelho sem o prepend
  (9 exemplos, 6 falhas), verde com ele.
- Focados: agent_bots_controller_spec, robos_sem_espelho_spec, soft_delete (request e service), inbox_connector
  (e concorrência): 55 exemplos, 0 falhas.
- `autonomia:guia:formatos` regerado; `autonomia:guia:formatos:check` em dia; `guia:check` e `i18n:fork:check` ok.
