/* global axios */
// Reagir e editar pelo painel na caixa WAHA comum (chat#1709, fase 3). Só aparece com a ação no campo
// `whatsapp_api_message_actions` da conversa; o servidor confere de novo (flag e motor).
import ApiClient from './ApiClient';

class WahaMessageActionsApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  react(conversationId, messageId, emoji) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/reaction`,
      { emoji }
    );
  }

  edit(conversationId, messageId, content) {
    return axios.patch(
      `${this.url}/${conversationId}/messages/${messageId}/content`,
      { content }
    );
  }
}

export default new WahaMessageActionsApi();
