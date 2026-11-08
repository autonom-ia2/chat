/* global axios */
import ApiClient from '../ApiClient';

// #1426 (tema 4b) — as conferências e o autoteste do material do agente (gaveta "O que sabe", Fase 2).
// A lista de materiais segue em ./sources.js; daqui vêm os problemas (um por vez) e o autoteste.
class AutonomiaMaterialAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  get(agentId) {
    return axios.get(`${this.url}/${agentId}/material`);
  }

  resolver(agentId, problemaId, escolha) {
    return axios.post(
      `${this.url}/${agentId}/material/problemas/${encodeURIComponent(problemaId)}/resolver`,
      { escolha }
    );
  }

  pedirAutoteste(agentId) {
    return axios.post(`${this.url}/${agentId}/material/autoteste`);
  }
}

export default new AutonomiaMaterialAPI();
