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
  connect(agentId, inboxId, { ativar = false } = {}) {
    const corpo = ativar
      ? { inbox_id: inboxId, ativar: true }
      : { inbox_id: inboxId };
    return axios.post(`${this.url}/${agentId}/channels`, corpo);
  }

  disconnect(agentId, inboxId) {
    return axios.delete(`${this.url}/${agentId}/channels/${inboxId}`);
  }
}

export default new AutonomiaChannelsAPI();
