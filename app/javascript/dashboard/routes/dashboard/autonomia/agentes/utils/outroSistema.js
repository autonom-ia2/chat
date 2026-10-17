// #1648 — agente de outro sistema (AgentBot webhook) na jornada de Agentes.
// A API de robôs já esconde os espelhos dos agentes da plataforma (#1626); os
// robôs de sistema (sem conta) também não são agentes da conta.
export const agentesDeOutroSistema = bots =>
  (bots || []).filter(bot => !bot.system_bot);

// Os canais (leitura de canais ocupados, L2) em que o agente de outro sistema
// atende primeiro: AgentBotInbox dele, ativo (`operating`).
export const canaisDoAgenteDeOutroSistema = (canais, botId) =>
  (canais || []).filter(
    canal =>
      canal.occupied_by?.kind === 'external' &&
      String(canal.occupied_by.agent_bot_id) === String(botId) &&
      canal.occupied_by.operating === true
  );
