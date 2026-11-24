/* global axios */

import ApiClient from './ApiClient';

// Ritmo de envio da conta (#3063): limite de mensagens por cliente, intervalo mínimo (#3101) e horário de envio.
// GET   .../ritmo_de_envio → { payload: { limite, intervalo, horario, fuso } }
// PATCH .../ritmo_de_envio { limite: { mensagens, dias } | null, intervalo: { horas } | null,
//                            horario: { inicio, fim, dias_da_semana } | null }
class RitmoDeEnvioAPI extends ApiClient {
  constructor() {
    super('ritmo_de_envio', { accountScoped: true });
  }

  buscar() {
    return axios.get(this.url);
  }

  salvar(ritmo) {
    return axios.patch(this.url, ritmo);
  }
}

export default new RitmoDeEnvioAPI();
