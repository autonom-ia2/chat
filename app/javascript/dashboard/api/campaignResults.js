/* global axios */
// Campaign result and Gestão overview (#1007). Contract: docs/campaigns/publicos/resultado-1007.md.
//   GET campaign_journey/results/:channel/:id            → { payload: { campaign, totals, filters, crm } }
//   GET campaign_journey/results/:channel/:id/recipients → { payload: { rows, meta } }
//   GET campaign_journey/results/:channel/:id/export     → masked CSV (campaign_manage)
//   GET campaign_journey/results/email/:id/period?period= → { payload: { period, since, until, sent, … } } (#990)
//   GET campaign_journey/overview?days=&channel=&page=   → { payload: { period, totals, campaigns, meta,
//                                                            duas_versoes_esperando (#3099) } }
//   POST campaign_journey/results/:channel/:id/vencedora { versao } → { payload: <bloco duas_versoes> } (#3099)
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

  getPeriodMetrics(channel, id, period, { signal } = {}) {
    return axios.get(`${this.resultUrl(channel, id)}/period`, {
      params: { period },
      signal,
    });
  }

  // #3099: a versão que vai para o resto do público (campaign_send). Outra versão já escolhida → 422.
  escolherVersao(channel, id, versao) {
    return axios.post(`${this.resultUrl(channel, id)}/vencedora`, { versao });
  }

  getOverview({ days, channel, page = 1, signal } = {}) {
    return axios.get(`${this.url}/overview`, {
      params: { days, channel: channel || undefined, page },
      signal,
    });
  }
}

export default new CampaignResultsAPI();
