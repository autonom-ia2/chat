/* global axios */
import ApiClient from './ApiClient';

// #2001 (F6) — CRM › Números › "De onde vieram os clientes":
// GET crm/numeros/origens?mes=AAAA-MM&funil=<id>|todos, e o relatório baixado
// (PDF ou planilha) com os mesmos números, montado no servidor.
class CrmNumerosOrigensAPI extends ApiClient {
  constructor() {
    super('crm/numeros/origens', { accountScoped: true });
  }

  show(params) {
    return axios.get(this.url, { params });
  }

  // formato: 'pdf' | 'planilha'. Responde o arquivo (blob).
  report(formato, params) {
    return axios.get(`${this.url}/report`, {
      params: { ...params, formato },
      responseType: 'blob',
    });
  }
}

export default new CrmNumerosOrigensAPI();
