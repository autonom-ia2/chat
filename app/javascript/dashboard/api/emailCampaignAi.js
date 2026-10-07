/* global axios */
import ApiClient from './ApiClient';
import { pollAiRequest } from '../helper/aiRequestPolling';

class EmailCampaignAiAPI extends ApiClient {
  constructor() {
    super('email_campaigns/ai', { accountScoped: true });
  }

  // brand (#1076): { brand_kit_id | brand_import_id, brand_mode } — omitted, the default identity.
  generate({
    campaignId,
    brief,
    placeholders,
    assets = [],
    baseMjml,
    brand = {},
  }) {
    return axios.post(`${this.url}/generate`, {
      campaign_id: campaignId,
      brief,
      placeholders,
      assets,
      base_mjml: baseMjml,
      ...brand,
    });
  }

  rewrite({ text, instruction }) {
    return pollAiRequest(
      axios.post(`${this.url}/rewrite`, { text, instruction })
    );
  }

  // Polling de fallback do estado da geração assíncrona (o caminho feliz é o ActionCable).
  status(campaignId) {
    return axios.get(`${this.url}/campaigns/${campaignId}/status`);
  }
}

export default new EmailCampaignAiAPI();
