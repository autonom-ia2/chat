/* global axios */
import ApiClient from './ApiClient';

// Comentários na caixa (#2215): the Instagram comment a conversation was born
// from (#2212), and the actions on it without leaving the conversation:
// public reply, hide/show and delete (ComentarioDaConversaController).
//
// GET    → { status, comentario, pode }
//          status: ok | needs_permission | apagado | meta_unavailable
// POST   responder { content } → { resposta: { texto } }
// POST   esconder  { hidden }  → { escondido }
// DELETE                       → { status: 'apagado' }
//
// Text goes in `content` only (the Rails log filters it).
class ComentarioDaConversaAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  urlDe(conversationId) {
    return `${this.url}/${conversationId}/comentario`;
  }

  get(conversationId) {
    return axios.get(this.urlDe(conversationId));
  }

  responder(conversationId, content) {
    return axios.post(`${this.urlDe(conversationId)}/responder`, { content });
  }

  esconder(conversationId, hidden) {
    return axios.post(`${this.urlDe(conversationId)}/esconder`, { hidden });
  }

  apagar(conversationId) {
    return axios.delete(this.urlDe(conversationId));
  }
}

export default new ComentarioDaConversaAPI();
