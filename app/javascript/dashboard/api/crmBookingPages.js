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

  // `applyToProfile` (#1298): a foto vira também a foto do perfil de quem
  // envia. O servidor só aceita quando quem envia é a pessoa da página.
  uploadImage(id, kind, file, { applyToProfile = false } = {}) {
    const body = new FormData();
    body.append('file', file);
    if (applyToProfile) body.append('apply_to_profile', 'true');
    return axios.post(`${this.url}/${id}/${kind}`, body);
  }

  // Identidade salva da conta (#1289): usar nesta página e salvar a partir dela.
  applyIdentity(id) {
    return axios.post(`${this.url}/${id}/apply_identity`);
  }

  saveIdentity(id) {
    return axios.post(`${this.url}/${id}/save_identity`);
  }

  // Endereço da página (#1282): com `name`, diz se está livre; só com `title`,
  // sugere um. `pageId` é a página que já pode ser a dona do nome.
  shortName({ name, title, pageId } = {}) {
    return axios.get(`${this.url}/short_name`, {
      params: { name, title, page_id: pageId },
    });
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

  // Modelos de aviso do WhatsApp oficial (#1272): a IA sugere um por aviso
  // entre os aprovados da caixa; criar enfileira o envio à Meta dos que faltam
  // e `noticeTemplateRequests` acompanha o estado de cada um.
  noticeTemplateSuggestions(id, inboxId, kinds) {
    return axios.post(`${this.url}/${id}/notice_template_suggestions`, {
      inbox_id: inboxId,
      kinds,
    });
  }

  noticeTemplateRequests(id, inboxId) {
    return axios.get(`${this.url}/${id}/notice_templates`, {
      params: { inbox_id: inboxId },
    });
  }

  createNoticeTemplates(id, inboxId, kinds) {
    return axios.post(`${this.url}/${id}/notice_templates/create`, {
      inbox_id: inboxId,
      kinds,
    });
  }

  // Passar reuniões (#1195): `pageId` vazio = todas as páginas. A prévia não grava.
  reassignPreview({ fromUserId, toUserId, pageId }) {
    return axios.get(`${this.url}/reassign_preview`, {
      params: reassignBody({ fromUserId, toUserId, pageId }),
    });
  }

  // Marcar pela agenda no painel (#1265): páginas publicadas que servem,
  // horários livres do dia e a reunião do card (ou do contato).
  bookable() {
    return axios.get(`${this.url}/bookable`);
  }

  slots(id, { date, duration } = {}) {
    return axios.get(`${this.url}/${id}/slots`, { params: { date, duration } });
  }

  book(
    id,
    { cardId, contactId, startsAt, duration, location, notify, requestId }
  ) {
    return axios.post(`${this.url}/${id}/meetings`, {
      card_id: cardId,
      contact_id: contactId,
      starts_at: startsAt,
      duration,
      location,
      notify,
      request_id: requestId,
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
