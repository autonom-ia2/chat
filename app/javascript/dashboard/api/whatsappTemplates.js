/* global axios */

import ApiClient from './ApiClient';

// Modelos de mensagem do WhatsApp oficial (#1330 backend, #1332 tela). Uma caixa por chamada: a conta do WhatsApp
// (WABA) é sempre a da caixa, nunca escolhida aqui.
// GET  inboxes/:inboxId/whatsapp_templates(?refresh=1)  → { payload: [template + perfil], meta: { last_synced_at } }
// POST inboxes/:inboxId/whatsapp_templates             { template: { name, language, category, components, friendly_name, fields, header_media } }
// PATCH/DELETE inboxes/:inboxId/whatsapp_templates/:id · GET …/:id/usage · POST …/media (multipart `file`)
// GET  whatsapp_template_inboxes  → { payload: [{ id, name, phone_number, group_id, group_name, reconnect, template_sends }] }
// GET  whatsapp_message_prices    → { payload: { currency, prices, free_tier, service_usage } }
// GET  campaign_journey/campaign_pauses · POST campaign_journey/campaign_pauses/:id/resume
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
    return axios.post(`${this.templatesUrl(inboxId)}/media`, body);
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
