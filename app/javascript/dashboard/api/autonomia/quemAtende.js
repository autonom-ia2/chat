/* global axios */
import ApiClient from '../ApiClient';

// #1648 — quem atende a caixa: { agentes: [{ id, name, papel, origem }] }.
// `papel`: 'porta' atende primeiro, 'area' recebe quando alguém passa.
// `origem`: 'plataforma' (agente da plataforma) ou 'webhook' (agente de outro
// sistema); a tela não separa os dois, só usa para saber onde abrir e trocar.
// MOCKUP (mockup-2): `trocar` ainda não existe no servidor. Ele faz a troca
// completa por trás (tira o anterior pelo caminho certo e põe o novo).
class AutonomiaQuemAtendeAPI extends ApiClient {
  constructor() {
    super('autonomia/inboxes', { accountScoped: true });
  }

  daCaixa(inboxId) {
    return axios.get(`${this.url}/${inboxId}/quem_atende`);
  }

  // `agente`: { id, origem } ou null (ninguém atende primeiro).
  trocar(inboxId, agente) {
    return axios.put(`${this.url}/${inboxId}/quem_atende`, { agente });
  }
}

export default new AutonomiaQuemAtendeAPI();
