/* global axios */
import ApiClient from './ApiClient';

// #2084/#2085 — "Este contato é" (interessado, parceiro do mercado, não é negócio):
//   GET crm/contacts/:id/relacao -> { relacao, cardsAbertos, podeEditar }
//   PUT crm/contacts/:id/relacao { relacao, arquivar_cards } -> { relacao, cardsArquivados, cardsNaoArquivados }
class CrmContatoRelacaoAPI extends ApiClient {
  constructor() {
    super('crm/contacts', { accountScoped: true });
  }

  show(contactId) {
    return axios.get(`${this.url}/${contactId}/relacao`);
  }

  update(contactId, { relacao, arquivarCards }) {
    return axios.put(`${this.url}/${contactId}/relacao`, {
      relacao,
      arquivar_cards: arquivarCards,
    });
  }
}

export default new CrmContatoRelacaoAPI();
