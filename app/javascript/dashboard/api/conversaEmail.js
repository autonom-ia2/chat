/* global axios */
import ApiClient from './ApiClient';

// Conversa de e-mail nova (#1786): ditado da resposta (a fala vira texto).
class ConversaEmailAPI extends ApiClient {
  constructor() {
    super('conversa_canal/ditados', { accountScoped: true });
  }

  ditadoDisponivel() {
    return axios.get(`${this.url}/disponivel`);
  }

  ditar(audio) {
    const corpo = new FormData();
    corpo.append('audio', audio, 'ditado');
    return axios.post(this.url, corpo);
  }
}

export default new ConversaEmailAPI();
