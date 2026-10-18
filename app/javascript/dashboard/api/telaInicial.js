/* global axios */
import ApiClient from './ApiClient';

// #1801 — o resumo da tela inicial da caixa (só leitura).
class TelaInicialAPI extends ApiClient {
  constructor() {
    super('tela_inicial', { accountScoped: true });
  }

  resumo() {
    return axios.get(`${this.url}/resumo`);
  }
}

export default new TelaInicialAPI();
