/* global axios */
import ApiClient from './ApiClient';

// O "+" da conversa com a cara do canal (#1702): busca de endereço (Google) e
// formulários aprovados da caixa (Meta).
class ConversaCanalAPI extends ApiClient {
  constructor() {
    super('conversa_canal', { accountScoped: true });
  }

  // `sessao`: um id por janela aberta; o Google cobra sugestões + detalhe como uma busca só.
  sugerirLugares(texto, sessao) {
    return axios.get(`${this.url}/lugares`, {
      params: { termo: texto, sessao },
    });
  }

  lugar(placeId, sessao) {
    return axios.get(`${this.url}/lugares/${encodeURIComponent(placeId)}`, {
      params: { sessao },
    });
  }

  formularios(inboxId) {
    return axios.get(`${this.url}/formularios`, {
      params: { inbox_id: inboxId },
    });
  }

  primeiraTela(inboxId, flowId) {
    return axios.get(
      `${this.url}/formularios/${encodeURIComponent(flowId)}/primeira_tela`,
      { params: { inbox_id: inboxId } }
    );
  }
}

export default new ConversaCanalAPI();
