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

  // "Sign in with Facebook" (#1069): the code from Facebook Login for Business
  // is exchanged and tested on the server, like update. 422 with error
  // 'login_failed', 'missing_ads_read', 'no_ad_account' or 'meta_unavailable'.
  facebookLogin(code) {
    return axios.post(`${this.url}/facebook_login`, { code });
  }

  // mode: 'partner' | 'token' | 'facebook_login' → { ad_accounts: [...] },
  // recommended first.
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

  // Daily panel (#1088, #1110): { panel: { days, from, to, currency, totals, ads,
  // confidence, meta_comparison, response_time, advice, synced_at, refreshing } }.
  // Also asks Meta for today's numbers.
  panel(days) {
    return axios.get(`${this.url}/panel`, { params: { days } });
  }

  // One step of the money path opened inside the panel (#1110, F5) →
  // { list: null | { step, days, total, items: [PathItem] } }, at most 50 items.
  // step: 'conversations' | 'quotes' | 'sales' | 'slow_replies'.
  panelList(step, days) {
    return axios.get(`${this.url}/panel_list`, { params: { step, days } });
  }

  // One ad from the inside (#1088, F3b): { ad: null } without data, or
  // { ad: { ...numbers, verdict, account_average_cost_per_sale, reason, daily,
  // quotes_list } }. Only reads the database; never calls Meta.
  panelAd(adId, days) {
    return axios.get(`${this.url}/panel_ad`, {
      params: { ad_id: adId, days },
    });
  }

  // AI reads the stages and answers { suggestions: [{ stage_id, type, reason }] }.
  suggestStages(pipelineId) {
    return pollAiRequest(
      axios.post(`${this.url}/suggest_stages`, { pipeline_id: pipelineId })
    );
  }

  // "What to do today" (#1110, F5): asks the AI to write the advice of the day
  // when panel.advice.writer.status is 'pending' → { daily_action: null | Advice },
  // Advice = { run_id, local_date, rules_version, writer: { status, reason },
  // actions: [1 to 3] }. `days` is accepted and ignored by the server.
  dailyAction(days) {
    return pollAiRequest(axios.post(`${this.url}/daily_action`, { days }));
  }

  // The person went to the work of one advice action: records opened_at once.
  openAdvice(id) {
    return axios.post(`${this.url}/advisor_actions/${id}/open`);
  }

  // "Done" (or "Got it" on auction pressure). 422 not_open when no longer open.
  acceptAdvice(id) {
    return axios.post(`${this.url}/advisor_actions/${id}/accept`);
  }

  // "Dismiss": the action leaves today's list and does not come back today.
  dismissAdvice(id) {
    return axios.post(`${this.url}/advisor_actions/${id}/dismiss`);
  }

  // Suggested message to resume a stalled quote. Never sent by the server →
  // { quote_message: { card_id, conversation_id, applies, reason, message,
  //   source_quote } }.
  quoteMessage(cardId) {
    return pollAiRequest(
      axios.post(`${this.url}/quote_message`, { card_id: cardId })
    );
  }
}

export default new CrmMetaAdsConnectionAPI();
