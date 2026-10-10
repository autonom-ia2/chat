/* global axios */
import ApiClient from './ApiClient';

// Anúncios da Meta (#1100, F4b): resumo diário e alerta no WhatsApp do dono
// (docs/crm/anuncios-meta-f4.md §2 e §3). Vem desligado; só administrador.
class CrmMetaAdsWhatsappReportAPI extends ApiClient {
  constructor() {
    super('crm/meta_ads_connection/whatsapp_report', { accountScoped: true });
  }

  // { whatsapp_report: null } sem conexão, ou { whatsapp_report: { enabled,
  //   alert_enabled, inbox_id, phone, last_*, origins, template_texts, schedule } }.
  get() {
    return axios.get(this.url);
  }

  // payload: { enabled?, alert_enabled?, inbox_id?, phone? }; chaves ausentes
  // ficam como estão. 422 { error } com o código da regra.
  update(payload) {
    return axios.patch(this.url, { whatsapp_report: payload });
  }

  // Envia agora o resumo de ontem, com a origem e o destino salvos →
  // { sent, sent_at }. 429 { error: 'rate_limited' } depois de 3 por hora.
  sendTest() {
    return axios.post(`${this.url}/test`);
  }
}

export default new CrmMetaAdsWhatsappReportAPI();
