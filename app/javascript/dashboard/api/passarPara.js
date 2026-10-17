/* global axios */
// #1593 — "Passar para…" na conversa (Api::V1::Accounts::Conversations::PassarParaController).
//   GET  /conversations/:id/passar_para → { fase2, sem_robo, pessoas, agentes, com_ia, origem }
//   POST /conversations/:id/passar_para { destino: { tipo: 'pessoa' | 'ia', id } } → o mesmo, mais `assignee` quando
//        uma pessoa assumiu. Recusa: 422 com `codigo` (a tela diz o porquê em linguagem simples).
import ApiClient from './ApiClient';

class PassarParaAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  quemPodeReceber(conversaId) {
    return axios.get(`${this.url}/${conversaId}/passar_para`);
  }

  passar(conversaId, destino) {
    return axios.post(`${this.url}/${conversaId}/passar_para`, { destino });
  }
}

export default new PassarParaAPI();
