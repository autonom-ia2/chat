/* global axios */
import ApiClient from '../ApiClient';

// #1648 — quais agentes da plataforma atendem a caixa ({ agentes: [{ id, name,
// papel: 'porta' | 'area' }] }). Sem flag: a aba "Agente externo" da caixa lê
// daqui para travar a escolha, com a mesma regra do servidor.
class AutonomiaQuemAtendeAPI extends ApiClient {
  constructor() {
    super('autonomia/inboxes', { accountScoped: true });
  }

  daCaixa(inboxId) {
    return axios.get(`${this.url}/${inboxId}/quem_atende`);
  }
}

export default new AutonomiaQuemAtendeAPI();
