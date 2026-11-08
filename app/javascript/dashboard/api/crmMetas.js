/* global axios */
import ApiClient from './ApiClient';

// #1991 — gaveta "Metas do mês" de CRM › Números (GET/PUT crm/metas). Sempre o
// mês de hoje, no fuso da conta; valores em reais inteiros, na moeda do funil.
class CrmMetasAPI extends ApiClient {
  constructor() {
    super('crm/metas', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  // mes: o mês que a gaveta mostrou; se já virou, o servidor recusa (422).
  salvar({ mes, funis }) {
    return axios.put(this.url, { mes, funis });
  }
}

export default new CrmMetasAPI();
