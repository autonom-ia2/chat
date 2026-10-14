// #1366 — regras do painel antigo (flag autonomia_agents_journey desligada) para pôr o agente no ar.

// Conectar e ativar é um passo só no servidor (`ativar`): sem canal o agente não pode ficar ativo, e
// a conexão que falha não liga nada. Publicar (PanelPublish) e o fim do wizard (AgentBuilderPage).
export const publicarNoCanal = (store, agentId, inboxId) =>
  store.dispatch('autonomiaChannels/connect', {
    agentId,
    inboxId,
    ativar: true,
  });

// O botão de status do cabeçalho (AgentPanelPage): ativar quem não tem onde trabalhar é escolher o
// canal na aba Publicar, nunca ligar no vazio (o servidor recusaria com 422).
export const ativarPedeCanal = (agent, proximoStatus) =>
  proximoStatus === 'active' && agent?.tem_onde_trabalhar === false;
