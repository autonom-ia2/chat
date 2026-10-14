/* global axios */

import ApiClient from './ApiClient';

// Conversa aberta na campanha do WhatsApp oficial (#1335,
// docs/campaigns/modelos-whatsapp/conversa-aberta.md).
// GET  .../campaign_journey/conversa_aberta?campaign_import_id=&inbox_id=&categoria=
// POST .../campaign_journey/conversa_aberta/escrever
class ConversaAbertaAPI extends ApiClient {
  constructor() {
    super('campaign_journey/conversa_aberta', { accountScoped: true });
  }

  contagem({ campaignImportId, inboxId, categoria }) {
    return axios.get(this.url, {
      params: {
        campaign_import_id: campaignImportId,
        inbox_id: inboxId,
        categoria,
      },
    });
  }

  escrever(body) {
    return axios.post(`${this.url}/escrever`, body);
  }
}

export default new ConversaAbertaAPI();
