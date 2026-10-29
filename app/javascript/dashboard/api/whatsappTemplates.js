/* global axios */

import ApiClient from './ApiClient';
import { pollAiRequest } from '../helper/aiRequestPolling';

// O job leva até 25 s por tentativa, com 1 nova tentativa, mais a fila (#1333);
// a tela desiste depois disto.
const SUGGESTION_POLL = { intervalMs: 1500, timeoutMs: 120 * 1000 };
// Vídeo que o WhatsApp não entrega é convertido num job (até 5 min de ffmpeg,
// mais a fila) e a subida volta 202 (#2370).
const MEDIA_POLL = { intervalMs: 2000, timeoutMs: 10 * 60 * 1000 };

// Modelos de mensagem do WhatsApp oficial (#1330 backend, #1332 tela). Uma caixa por chamada: a conta do WhatsApp
// (WABA) é sempre a da caixa, nunca escolhida aqui.
// GET  inboxes/:inboxId/whatsapp_templates(?refresh=1)  → { payload: [template + perfil], meta: { last_synced_at } }
// POST inboxes/:inboxId/whatsapp_templates             { template: { name, language, category, components, friendly_name, fields, header_media } }
// PATCH/DELETE inboxes/:inboxId/whatsapp_templates/:id · GET …/:id/usage · POST …/media (multipart `file`)
// GET  whatsapp_template_inboxes  → { payload: [{ id, name, phone_number, group_id, group_name, reconnect, template_sends }] }
// GET  whatsapp_message_prices    → { payload: { currency, prices, free_tier, service_usage } }
// GET  campaign_journey/campaign_pauses · POST campaign_journey/campaign_pauses/:id/resume
// GET  inboxes/:inboxId/whatsapp_catalog            → { catalog: { name, product_count } | null } (#1418)
// GET  inboxes/:inboxId/whatsapp_catalog/products?q=&after= → { payload: [{ id, name, price, sale_price, image_url, available }], meta: { after } }
//      …/products?ids[]= → os produtos escolhidos, relidos (#1716)
// POST whatsapp_template_suggestions  { mode: create|improve, goal | text + improvements, tone, category } (#1333)
//   → 202 + poll_url (job); `suggest` busca o resultado: { payload } ou { error, message }
// GET  whatsapp_template_consent · POST { operacao: ligar|desligar, marcas, versao_aviso } (#1586)
class WhatsappTemplatesAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  templatesUrl(inboxId) {
    return `${this.url}inboxes/${inboxId}/whatsapp_templates`;
  }

  getInboxes() {
    return axios.get(`${this.url}whatsapp_template_inboxes`);
  }

  getPrices() {
    return axios.get(`${this.url}whatsapp_message_prices`);
  }

  getTemplates(inboxId, { refresh = false } = {}) {
    return axios.get(this.templatesUrl(inboxId), {
      params: refresh ? { refresh: 1 } : {},
    });
  }

  createTemplate(inboxId, template) {
    return axios.post(this.templatesUrl(inboxId), { template });
  }

  updateTemplate(inboxId, templateId, template) {
    return axios.patch(`${this.templatesUrl(inboxId)}/${templateId}`, {
      template,
    });
  }

  deleteTemplate(inboxId, templateId) {
    return axios.delete(`${this.templatesUrl(inboxId)}/${templateId}`);
  }

  getUsage(inboxId, templateId) {
    return axios.get(`${this.templatesUrl(inboxId)}/${templateId}/usage`);
  }

  uploadMedia(inboxId, file) {
    const body = new FormData();
    body.append('file', file);
    return pollAiRequest(
      axios.post(`${this.templatesUrl(inboxId)}/media`, body),
      MEDIA_POLL
    );
  }

  suggest(body) {
    return pollAiRequest(
      axios.post(`${this.url}whatsapp_template_suggestions`, body),
      SUGGESTION_POLL
    );
  }

  getCatalog(inboxId) {
    return axios.get(`${this.url}inboxes/${inboxId}/whatsapp_catalog`);
  }

  getCatalogProducts(inboxId, { search = '', after = '', ids = [] } = {}) {
    return axios.get(
      `${this.url}inboxes/${inboxId}/whatsapp_catalog/products`,
      {
        params: {
          ...(search ? { q: search } : {}),
          ...(after ? { after } : {}),
          ...(ids.length ? { ids } : {}),
        },
      }
    );
  }

  // Autorização do dono para o sistema criar modelos (#1586).
  getConsent() {
    return axios.get(`${this.url}whatsapp_template_consent`);
  }

  updateConsent({ acao, marcas, versaoAviso }) {
    return axios.post(`${this.url}whatsapp_template_consent`, {
      operacao: acao,
      marcas,
      versao_aviso: versaoAviso,
    });
  }

  getCampaignPauses() {
    return axios.get(`${this.url}campaign_journey/campaign_pauses`);
  }

  resumeCampaignPause(pauseId) {
    return axios.post(
      `${this.url}campaign_journey/campaign_pauses/${pauseId}/resume`
    );
  }
}

export default new WhatsappTemplatesAPI();
