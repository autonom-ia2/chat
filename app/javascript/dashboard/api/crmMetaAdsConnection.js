/* global axios */
import ApiClient from './ApiClient';
import { pollAiRequest } from 'dashboard/helper/aiRequestPolling';

// Meta ads connection of the account (docs/crm/origens-nomes-meta.md §2 and
// docs/crm/anuncios-meta-f1.md). The token only goes out on update; no
// response ever carries it back.
class CrmMetaAdsConnectionAPI extends ApiClient {
  constructor() {
    super('crm/meta_ads_connection', { accountScoped: true });
  }

  // { configured, status, mode, ad_account, pixel, destinations, partner,
  //   whatsapp_portfolio, sales_signal, ... }
  get() {
    return axios.get(this.url);
  }

  // Meta tests the token before it is saved: 422 with error
  // 'missing_ads_read' or 'invalid_token' when it cannot be used.
  update(accessToken) {
    return axios.put(this.url, { access_token: accessToken });
  }

  remove() {
    return axios.delete(this.url);
  }

  // mode: 'partner' | 'token' → { ad_accounts: [...] }, recommended first.
  adAccounts(mode) {
    return axios.get(`${this.url}/ad_accounts`, { params: { mode } });
  }

  pixels(mode, adAccountId) {
    return axios.get(`${this.url}/pixels`, {
      params: { mode, ad_account_id: adAccountId },
    });
  }

  // Reads the account, its 30-day spend and the Pixel before saving.
  select({ mode, adAccountId, pixelId }) {
    return axios.post(`${this.url}/selection`, {
      mode,
      ad_account_id: adAccountId,
      pixel_id: pixelId,
    });
  }

  // { whatsapp: bool, site: bool }
  updateDestinations(destinations) {
    return axios.patch(`${this.url}/destinations`, { destinations });
  }

  // Step 4: active pipelines tied to the official WhatsApp →
  // { funnels: [{ id, name, numbers, enabled, stages, missing }],
  //   unlinked_numbers, ai_available }
  funnels() {
    return axios.get(`${this.url}/funnels`);
  }

  // stages: [{ id, funnel_stage_type }] with 'none' to clear a stage.
  // Turns on sales and stage changes for this pipeline only.
  saveFunnel(pipelineId, stages) {
    return axios.patch(`${this.url}/funnel`, {
      pipeline_id: pipelineId,
      stages,
    });
  }

  stopFunnel(pipelineId) {
    return axios.patch(`${this.url}/funnel`, {
      pipeline_id: pipelineId,
      enabled: false,
    });
  }

  // Collection (#1073): last day read for the ad account →
  // { insights: { synced_at, refreshing, date, spend, currency, conversations } }.
  // Asks Meta for today's numbers when they are older than 5 minutes; the end
  // of that read arrives as crm.meta_ads.insights_updated.
  insights() {
    return axios.post(`${this.url}/insights`);
  }

  // Daily panel (#1088): { panel: { days, from, to, currency, totals, ads, action,
  // confidence, synced_at, refreshing } }. Also asks Meta for today's numbers.
  panel(days) {
    return axios.get(`${this.url}/panel`, { params: { days } });
  }

  // AI reads the stages and answers { suggestions: [{ stage_id, type, reason }] }.
  suggestStages(pipelineId) {
    return pollAiRequest(
      axios.post(`${this.url}/suggest_stages`, { pipeline_id: pipelineId })
    );
  }
}

export default new CrmMetaAdsConnectionAPI();
