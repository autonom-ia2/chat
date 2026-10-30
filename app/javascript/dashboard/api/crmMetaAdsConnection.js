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

  // Reads the account, its 30-day spend and the Pixel before saving. noSite:
  // without a Pixel, the person chose "I have no website" on purpose (#2343).
  select({ mode, adAccountId, pixelId, noSite = false }) {
    return axios.post(`${this.url}/selection`, {
      mode,
      ad_account_id: adAccountId,
      pixel_id: pixelId,
      no_site: noSite,
    });
  }

  // { whatsapp: bool, site: bool }
  updateDestinations(destinations) {
    return axios.patch(`${this.url}/destinations`, { destinations });
  }

  // Destino (#2338): páginas do site, sem cliques nem vendas (meta_ads_view), e ligar uma ali mesmo
  // (meta_ads_manage) → { payload }.
  sitePages() {
    return axios.get(`${this.url}/site_pages`);
  }

  createSitePage({ name, inbox_id, allowed_origins }) {
    return axios.post(`${this.url}/site_pages`, {
      name,
      inbox_id,
      allowed_origins,
    });
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

  // Daily panel (#1088, #1110): { panel: { period, days, from, to, open, currency,
  // totals, ads, confidence, meta_comparison, response_time, advice, synced_at,
  // refreshing } }. Also asks Meta for today's numbers.
  // period (#2011): '7d' | '30d' | '90d' | 'this_month' | 'last_month' | 'all'.
  panel(period) {
    return axios.get(`${this.url}/panel`, { params: { period } });
  }

  // One step of the money path opened inside the panel (#1110, F5) →
  // { list: null | { step, period, days, total, items: [PathItem] } }, at most 50
  // items. step: 'conversations' | 'quotes' | 'sales' | 'slow_replies'.
  panelList(step, period) {
    return axios.get(`${this.url}/panel_list`, { params: { step, period } });
  }

  // One ad from the inside (#1088, F3b): { ad: null } without data, or
  // { ad: { ...numbers, verdict, account_average_cost_per_sale, reason, daily,
  // quotes_list } }. Only reads the database; never calls Meta.
  panelAd(adId, period) {
    return axios.get(`${this.url}/panel_ad`, {
      params: { ad_id: adId, period },
    });
  }

  // Downloaded report (#1960): the panel of the period as a landscape PDF or a
  // spreadsheet. formato: 'pdf' | 'planilha'. Answers the file (blob).
  report(formato, period) {
    return axios.get(`${this.url}/report`, {
      params: { formato, period },
      responseType: 'blob',
    });
  }

  // Your posts (#2199): organic results of the Facebook Page and Instagram.
  // days: 7 | 30 | 90 → { days, from, to, page, instagram }; each place has
  // status 'ok' | 'needs_permission' | 'not_connected'. 503 'meta_unavailable'.
  organico(days) {
    return axios.get(`${this.url}/organico`, { params: { days } });
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

  // Ad management (#2161, flag meta_ads_gestao), live from Meta →
  // { management: { status, effective_status, mode, can_change, needs_login,
  //   post: { message, created_time, permalink_url, page_name, reactions,
  //   comments, shares } | null } }. 404 ad_not_found / not_connected.
  adManagement(adId) {
    return axios.get(`${this.url}/ads/${encodeURIComponent(adId)}/management`);
  }

  // status = 'ACTIVE' | 'PAUSED' → { status, held_by? }. With the flag
  // meta_ads_criar and status ACTIVE, held_by is 'campaign' | 'adset' when a
  // paused parent still keeps the ad from running, or null. 422
  // cannot_change, meta_refused, meta_unavailable.
  setAdStatus(adId, status) {
    return axios.post(`${this.url}/ads/${encodeURIComponent(adId)}/status`, {
      status,
    });
  }

  // Simple ads manager (#2198, flag meta_ads_criar; 404 without it).
  // What the person can pick to create → { options: { needs_login,
  // facebook_login, kinds, pages, instagram, whatsapp_numbers, posts, images,
  // currency, min_daily, max_daily, destinations, placements_by_destination } }.
  createOptions() {
    return axios.get(`${this.url}/create_options`);
  }

  // Posts of the chosen Page and of its Instagram, to boost (#2339) →
  // { posts, instagram_posts, posts_error }.
  boostPosts(pageId) {
    return axios.get(`${this.url}/boost_posts`, {
      params: { page_id: pageId },
    });
  }

  // Photo or video from the device (multipart, field `file`) →
  // { media: { kind: 'image', hash, url, width, height } } or
  // { media: { kind: 'video', video_id } }. 422 invalid_media,
  // media_too_large, meta_unavailable, meta_refused.
  uploadMedia(file) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.url}/media`, form);
  }

  // New ad, always created PAUSED → { ad_id, name, status, budget }. The same
  // idempotency_key returns the same ad. 422 { error, nothing_created };
  // 409 { error: 'in_progress' } while that key is still being created.
  createAd(draft) {
    return axios.post(`${this.url}/ads`, draft);
  }

  // Budget and dates of the ad (adset or campaign that holds the money) →
  // { budget: { level, object_id, object_name, kind, amount, currency,
  //   start_time, end_time, started, ads_count, active_ads_count, min_daily,
  //   max_daily, can_change, adset_id } }. 404 ad_not_found /
  // budget_not_found; 422 meta_unavailable.
  adBudget(adId) {
    return axios.get(`${this.url}/ads/${encodeURIComponent(adId)}/budget`);
  }

  // { amount, end_time } → { budget } (the new one). 422 invalid_amount,
  // invalid_dates, cannot_change, meta_refused, meta_unavailable.
  updateAdBudget(adId, { amount, end_time: endTime }) {
    return axios.patch(`${this.url}/ads/${encodeURIComponent(adId)}/budget`, {
      amount,
      end_time: endTime,
    });
  }

  // Ads created here that are still paused →
  // { ads: [{ ad_id, name, created_at, budget }] }.
  pausedAds() {
    return axios.get(`${this.url}/paused_ads`);
  }

  // Pages granted at Facebook login → { pages: [{ id, name }] }.
  pages() {
    return axios.get(`${this.url}/pages`);
  }

  // Instagram comments of the ad (#2196, flag meta_ads_comentarios_instagram),
  // live from Meta → { status: ready | needs_login | not_connected | no_post,
  //   account, permalink_url, comments, total, next_cursor }.
  instagramComments(adId, after) {
    return axios.get(this.instagramCommentsUrl(adId), {
      params: after ? { after } : {},
    });
  }

  // Each action answers 422 { error } (invalid_text, needs_login,
  // meta_unavailable, meta_refused, private_reply_done,
  // private_reply_expired) or 404 comment_not_found.
  // The text goes as `content`, which the Rails log filters (#2327).
  replyInstagramComment(adId, commentId, content) {
    return axios.post(`${this.instagramCommentsUrl(adId, commentId)}/reply`, {
      content,
    });
  }

  hideInstagramComment(adId, commentId, hidden) {
    return axios.post(`${this.instagramCommentsUrl(adId, commentId)}/hide`, {
      hidden,
    });
  }

  deleteInstagramComment(adId, commentId) {
    return axios.delete(this.instagramCommentsUrl(adId, commentId));
  }

  // → { sent_at, conversation_path }
  privateReplyInstagramComment(adId, commentId, content) {
    return axios.post(
      `${this.instagramCommentsUrl(adId, commentId)}/private_reply`,
      { content }
    );
  }

  releaseInstagramPrivateReply(adId, commentId) {
    return axios.post(
      `${this.instagramCommentsUrl(adId, commentId)}/private_reply/release`
    );
  }

  instagramCommentsUrl(adId, commentId) {
    const base = `${this.url}/ads/${encodeURIComponent(adId)}/instagram_comments`;
    return commentId ? `${base}/${encodeURIComponent(commentId)}` : base;
  }

  // Facebook comments on the ad's Page post (#2197, flag
  // meta_ads_comentarios_facebook), live from Meta → { comments: { status,
  // permalink_url, comments, total, next_cursor } }; with `after`, the next
  // page → { comments: { comments, next_cursor } }.
  facebookComments(adId, after = null) {
    return axios.get(this.facebookCommentsUrl(adId), {
      params: after ? { after } : {},
    });
  }

  // Replies as the Page → { id }.
  // The text goes as `content`, which the Rails log filters.
  replyFacebookComment(adId, commentId, content) {
    return axios.post(
      `${this.facebookCommentsUrl(adId)}/${encodeURIComponent(commentId)}/reply`,
      { content }
    );
  }

  hideFacebookComment(adId, commentId, hidden) {
    return axios.patch(
      `${this.facebookCommentsUrl(adId)}/${encodeURIComponent(commentId)}`,
      { hidden }
    );
  }

  // Irreversible: the screen confirms first.
  deleteFacebookComment(adId, commentId) {
    return axios.delete(
      `${this.facebookCommentsUrl(adId)}/${encodeURIComponent(commentId)}`
    );
  }

  facebookCommentsUrl(adId) {
    return `${this.url}/ads/${encodeURIComponent(adId)}/facebook_comments`;
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
