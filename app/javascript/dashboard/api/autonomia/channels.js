/* global axios */
import ApiClient from '../ApiClient';

// Channels = the inboxes an agent is connected to. `get` returns both the
// connected inboxes and the eligible ones (each inbox can host only one agent).
class AutonomiaChannelsAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  get(agentId, { signal } = {}) {
    const endpoint = `${this.url}/${agentId}/channels`;
    return signal ? axios.get(endpoint, { signal }) : axios.get(endpoint);
  }

  connect(agentId, inboxId) {
    return axios.post(`${this.url}/${agentId}/channels`, { inbox_id: inboxId });
  }

  disconnect(agentId, inboxId) {
    return axios.delete(`${this.url}/${agentId}/channels/${inboxId}`);
  }
}

export default new AutonomiaChannelsAPI();
