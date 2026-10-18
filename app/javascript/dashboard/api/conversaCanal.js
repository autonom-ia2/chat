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

  // Reação do atendente (#1702): emoji '' tira a da empresa.
  reagir(conversationId, messageId, emoji) {
    return axios.post(`${this.url}/reacoes`, {
      conversation_id: conversationId,
      message_id: messageId,
      emoji,
    });
  }

  // Reação pela caixa WAHA cujo motor declara 'react' (#1709): o conector leva ao
  // WhatsApp. Fica fora do escopo `conversa_canal`: é a rota da própria mensagem.
  reagirPelaCaixa(conversationId, messageId, emoji) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/messages/${messageId}/reaction`,
      { emoji }
    );
  }

  // Encaminhar (#1702): conversas que o usuário vê, e o envio para até 5 delas.
  destinosParaEncaminhar(termo) {
    return axios.get(`${this.url}/encaminhamentos`, { params: { termo } });
  }

  encaminhar(conversationId, messageIds, conversationIds) {
    return axios.post(`${this.url}/encaminhamentos`, {
      conversation_id: conversationId,
      message_ids: messageIds,
      conversation_ids: conversationIds,
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
