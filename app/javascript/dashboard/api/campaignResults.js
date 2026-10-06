/* global axios */
// Campaign result and Gestão overview (#1007). Contract: docs/campaigns/publicos/resultado-1007.md.
//   GET campaign_journey/results/:channel/:id            → { payload: { campaign, totals, filters, crm } }
//   GET campaign_journey/results/:channel/:id/recipients → { payload: { rows, meta } }
//   GET campaign_journey/results/:channel/:id/export     → masked CSV (campaign_manage)
//   GET campaign_journey/overview?days=&channel=&page=   → { payload: { period, totals, campaigns, meta } }
import ApiClient from './ApiClient';

class CampaignResultsAPI extends ApiClient {
  constructor() {
    super('campaign_journey', { accountScoped: true });
  }

  resultUrl(channel, id) {
    return `${this.url}/results/${channel}/${id}`;
  }

  getResult(channel, id, { signal } = {}) {
    return axios.get(this.resultUrl(channel, id), { signal });
  }

  getRecipients(channel, id, { status, page = 1, signal } = {}) {
    return axios.get(`${this.resultUrl(channel, id)}/recipients`, {
      params: { status: status || undefined, page },
      signal,
    });
  }

  exportResult(channel, id, { status } = {}) {
    return axios.get(`${this.resultUrl(channel, id)}/export`, {
      params: { status: status || undefined },
      responseType: 'blob',
    });
  }

  getOverview({ days, channel, page = 1, signal } = {}) {
    return axios.get(`${this.url}/overview`, {
      params: { days, channel: channel || undefined, page },
      signal,
    });
  }
}

export default new CampaignResultsAPI();
