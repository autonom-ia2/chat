/* global axios */
import ApiClient from './ApiClient';

// Páginas de agendamento novas (#1187, F1-D): /api/v1/accounts/:accountId/crm/booking_pages.
// Herdados: get() lista, show(id), delete(id). O resto segue o contrato do
// BookingPagesController (F1-A): corpo do PATCH em `booking_page`, upload em `file`.
const reassignBody = ({ fromUserId, toUserId, pageId }) => {
  const body = { from_user_id: fromUserId, to_user_id: toUserId };
  if (pageId) body.page_id = pageId;
  return body;
};

class CrmBookingPagesAPI extends ApiClient {
  constructor() {
    super('crm/booking_pages', { accountScoped: true });
  }

  create({ templateKey, title } = {}) {
    const body = { template_key: templateKey };
    if (title) body.title = title;
    return axios.post(this.url, body);
  }

  update(id, bookingPage) {
    return axios.patch(`${this.url}/${id}`, { booking_page: bookingPage });
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  uploadImage(id, kind, file) {
    const body = new FormData();
    body.append('file', file);
    return axios.post(`${this.url}/${id}/${kind}`, body);
  }

  people(id) {
    return axios.get(`${this.url}/${id}/people`);
  }

  updatePeople(id, userIds) {
    return axios.put(`${this.url}/${id}/people`, { user_ids: userIds });
  }

  // "Testar no meu WhatsApp" (#1192): manda ao número um link igual ao do cliente.
  testInvite(id, phone) {
    return axios.post(`${this.url}/${id}/test_invite`, { phone });
  }

  // Passar reuniões (#1195): `pageId` vazio = todas as páginas. A prévia não grava.
  reassignPreview({ fromUserId, toUserId, pageId }) {
    return axios.get(`${this.url}/reassign_preview`, {
      params: reassignBody({ fromUserId, toUserId, pageId }),
    });
  }

  reassign({ fromUserId, toUserId, pageId }) {
    return axios.post(
      `${this.url}/reassign`,
      reassignBody({ fromUserId, toUserId, pageId })
    );
  }
}

export default new CrmBookingPagesAPI();
