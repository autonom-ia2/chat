/* global axios */
import ApiClient from './ApiClient';

// Spam e Lixeira da caixa de e-mail no painel (#1809).
class PastasDoEmailAPI extends ApiClient {
  constructor() {
    super('conversa_canal/pastas_do_email', { accountScoped: true });
  }

  ler(conversaId) {
    return axios.get(`${this.url}/${conversaId}`);
  }

  excluir(conversaId) {
    return axios.delete(`${this.url}/${conversaId}`);
  }

  mover(conversaId, pasta) {
    return axios.put(`${this.url}/${conversaId}`, { pasta });
  }
}

export default new PastasDoEmailAPI();
