/* global axios */
import ApiClient from './ApiClient';

// #1897 — CRM › Números por papel, visão "Só eu" (GET crm/numeros?mes=AAAA-MM).
// Quem abre vem da sessão; a resposta diz as visões que a pessoa pode ver.
class CrmNumerosAPI extends ApiClient {
  constructor() {
    super('crm/numeros', { accountScoped: true });
  }

  show(params) {
    return axios.get(this.url, { params });
  }
}

export default new CrmNumerosAPI();
