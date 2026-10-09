/* global axios */
import ApiClient from './ApiClient';
import { pollAiRequest } from '../helper/aiRequestPolling';

const generateIdempotencyKey = () =>
  (typeof window !== 'undefined' && window.crypto?.randomUUID?.()) ||
  `${Date.now()}-${Math.random().toString(36).slice(2)}`;

class CrmMeetingsApi extends ApiClient {
  constructor() {
    super('crm/meetings', { accountScoped: true });
  }

  meetingsUrl(accountId = this.accountIdFromRoute) {
    return `${this.apiVersion}/accounts/${accountId}/crm/meetings`;
  }

  create(accountId, payload, idempotencyKey = generateIdempotencyKey()) {
    const config = { headers: { 'Idempotency-Key': idempotencyKey } };
    return axios.post(this.meetingsUrl(accountId), payload, config);
  }

  index(accountId, params = {}) {
    return axios.get(this.meetingsUrl(accountId), { params });
  }

  show(accountId, meetingId) {
    return axios.get(`${this.meetingsUrl(accountId)}/${meetingId}`);
  }

  sync(accountId, meetingId, { force } = {}) {
    const url = `${this.meetingsUrl(accountId)}/${meetingId}/sync`;
    return axios.post(url, null, force ? { params: { force: true } } : {});
  }

  reschedule(accountId, meetingId, payload) {
    return axios.put(`${this.meetingsUrl(accountId)}/${meetingId}`, payload);
  }

  cancel(accountId, meetingId) {
    return axios.delete(`${this.meetingsUrl(accountId)}/${meetingId}`);
  }

  recordOutcome(accountId, meetingId, { outcome, notes } = {}) {
    const url = `${this.meetingsUrl(accountId)}/${meetingId}/record_outcome`;
    return axios.post(url, { meeting: { outcome, notes } });
  }

  // Dia da reunião (#1193): "Lembrar" (J4-A5) e o link para o cliente marcar
  // outro horário depois de faltar (J4-A6). Só com o toque do agente.
  remind(accountId, meetingId) {
    return axios.post(`${this.meetingsUrl(accountId)}/${meetingId}/remind`);
  }

  rebookLink(accountId, meetingId) {
    return axios.post(
      `${this.meetingsUrl(accountId)}/${meetingId}/rebook_link`
    );
  }

  // AI (S5): suggest best free times for a not-yet-created meeting (collection route).
  suggestTimes(
    accountId,
    { cardId, inboxId, date, durationMinutes, timezone } = {}
  ) {
    const url = `${this.meetingsUrl(accountId)}/suggest_times`;
    return pollAiRequest(
      axios.post(url, {
        card_id: cardId,
        inbox_id: inboxId,
        date,
        duration_minutes: durationMinutes,
        timezone,
      })
    );
  }

  // AI (S5): draft the meeting description/agenda from deal context (collection route).
  draftInvite(accountId, { cardId, title } = {}) {
    const url = `${this.meetingsUrl(accountId)}/draft_invite`;
    return pollAiRequest(axios.post(url, { card_id: cardId, title }));
  }

  // AI (S5): summarize a held meeting's outcome notes (member route).
  summarize(accountId, meetingId) {
    const url = `${this.meetingsUrl(accountId)}/${meetingId}/summarize`;
    return pollAiRequest(axios.post(url, null));
  }

  // Free/busy lookup lives on the calendar controller (crm/calendar), not crm/meetings.
  getAvailability(accountId, { inboxId, date, timezone } = {}) {
    const url = `${this.apiVersion}/accounts/${accountId}/crm/calendar/available_slots`;
    return axios.get(url, { params: { inbox_id: inboxId, date, timezone } });
  }

  createMeeting(accountId, payload, idempotencyKey) {
    return this.create(accountId, payload, idempotencyKey);
  }

  getMeetings(accountId, params = {}) {
    return this.index(accountId, params);
  }

  getMeeting(accountId, meetingId) {
    return this.show(accountId, meetingId);
  }
}

export default new CrmMeetingsApi();
