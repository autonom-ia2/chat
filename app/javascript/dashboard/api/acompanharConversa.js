/* global axios */
import ApiClient from './ApiClient';

// #2138: incluir ou tirar UMA pessoa de quem acompanha a conversa. POST e DELETE
// de participants só mexem nos ids enviados (participants_controller.rb, create e
// destroy); o PATCH de hoje grava a lista inteira e por isso não serve aqui.
class AcompanharConversaAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  incluir(conversationId, userId) {
    return axios.post(`${this.url}/${conversationId}/participants`, {
      user_ids: [userId],
    });
  }

  tirar(conversationId, userId) {
    return axios.delete(`${this.url}/${conversationId}/participants`, {
      data: { user_ids: [userId] },
    });
  }

  quemAcompanha(conversationId) {
    return axios.get(`${this.url}/${conversationId}/participants`);
  }
}

export default new AcompanharConversaAPI();
