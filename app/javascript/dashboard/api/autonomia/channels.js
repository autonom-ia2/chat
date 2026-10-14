/* global axios */
import ApiClient from '../ApiClient';

// Channels = the inboxes an agent is connected to. `get` returns both the
// connected inboxes and the eligible ones (each inbox can host only one agent).
class AutonomiaChannelsAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  get(agentId) {
    return axios.get(`${this.url}/${agentId}/channels`);
  }

  // `ativar` (#1366): "Começar a atender neste canal" — o servidor liga o agente parado junto com o
  // vínculo. Sem canal, o agente não pode ficar atendendo: ativar antes, sozinho, é recusado (422).
  // `papel: 'area'` (#1433, tema 13): agente da equipe — entra na caixa (que já tem principal
  // atendendo) para receber quando alguém passa, e o servidor já o liga. Só com a Fase 2.
  connect(agentId, inboxId, { ativar = false, papel = null } = {}) {
    const corpo = { inbox_id: inboxId };
    if (papel) corpo.papel = papel;
    else if (ativar) corpo.ativar = true;
    return axios.post(`${this.url}/${agentId}/channels`, corpo);
  }

  disconnect(agentId, inboxId) {
    return axios.delete(`${this.url}/${agentId}/channels/${inboxId}`);
  }
}

export default new AutonomiaChannelsAPI();
