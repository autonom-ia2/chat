/* global axios */
import ApiClient from './ApiClient';

// WhatsApp Híbrido (chat#1067): conexão WhatsApp API auxiliar de uma caixa WhatsApp Oficial.
class WhatsappHybridAPI extends ApiClient {
  constructor() {
    super('whatsapp_hybrid_connections', { accountScoped: true });
  }

  show(inboxId) {
    return axios.get(`${this.url}/${inboxId}`);
  }

  connect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/connect`);
  }

  requestCode(inboxId) {
    return axios.post(`${this.url}/${inboxId}/request_code`);
  }

  reconnect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reconnect`);
  }

  // chat#1487: pausa sem desvincular o aparelho; retomar religa sem QR.
  pause(inboxId) {
    return axios.post(`${this.url}/${inboxId}/pause`);
  }

  resume(inboxId) {
    return axios.post(`${this.url}/${inboxId}/resume`);
  }

  updateSettings(inboxId, settings) {
    return axios.patch(`${this.url}/${inboxId}`, settings);
  }

  disconnect(inboxId) {
    return axios.delete(`${this.url}/${inboxId}`);
  }
}

export default new WhatsappHybridAPI();
