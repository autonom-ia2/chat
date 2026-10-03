/* global axios */
import ApiClient from './ApiClient';

class AutomationsAPI extends ApiClient {
  constructor() {
    super('automation_rules', { accountScoped: true });
  }

  clone(automationId) {
    return axios.post(`${this.url}/${automationId}/clone`);
  }

  // #859 — o que a regra faria nas conversas recentes, sem executar nada:
  // { testavel, resultados: [{ conversation_id, display_id, contato, casou, faria }],
  //   sem_teste, depende_do_decisor }.
  ensaio(automationId, quantidade) {
    return axios.post(`${this.url}/${automationId}/ensaio`, { quantidade });
  }
}

export default new AutomationsAPI();
