/* global axios */
import ApiClient from './ApiClient';

// Link de agenda por cliente (#1190): /api/v1/accounts/:accountId/crm/booking_invites.
// index({ card_id | conversation_id | contact_id }) → { payload: [convites], pages: [{ id, title }] }
class CrmBookingInvitesAPI extends ApiClient {
  constructor() {
    super('crm/booking_invites', { accountScoped: true });
  }

  index(params = {}) {
    return axios.get(this.url, { params });
  }

  create({ bookingPageId, cardId, conversationId, contactId } = {}) {
    return axios.post(this.url, {
      booking_page_id: bookingPageId,
      card_id: cardId,
      conversation_id: conversationId,
      contact_id: contactId,
    });
  }

  deliver(id, { conversationId, text } = {}) {
    return axios.post(`${this.url}/${id}/deliver`, {
      conversation_id: conversationId,
      text,
    });
  }

  // O link foi copiado para mandar por outro canal: conta como enviado (#1194).
  copied(id) {
    return axios.post(`${this.url}/${id}/copied`);
  }

  cancel(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new CrmBookingInvitesAPI();
