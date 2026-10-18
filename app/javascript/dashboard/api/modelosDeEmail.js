/* global axios */
import ApiClient from './ApiClient';

// Modelos de e-mail das Campanhas no "+" da resposta de e-mail (#1786).
class ModelosDeEmailAPI extends ApiClient {
  constructor() {
    super('conversa_canal/modelos_de_email', { accountScoped: true });
  }

  listar() {
    return axios.get(this.url);
  }

  previa(id) {
    return axios.get(`${this.url}/${id}/previa`);
  }

  abrir(id, conversationId) {
    return axios.get(`${this.url}/${id}`, {
      params: { conversation_id: conversationId },
    });
  }

  // #1809: sem conversa (gaveta "Escrever"), os campos saem do contato escolhido.
  abrirParaContato(id, { contactId, inboxId }) {
    return axios.get(`${this.url}/${id}`, {
      params: { contact_id: contactId, inbox_id: inboxId },
    });
  }
}

export default new ModelosDeEmailAPI();
