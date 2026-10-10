/* global axios */
import ApiClient from './ApiClient';

// Painel de resultados do agendamento (#1194): /api/v1/accounts/:accountId/crm/booking_stats.
// show({ period: 7|30, scope: 'mine'|'team' }) → { period, scope, can_see_team, totals, origins }
// openedNotBooked({ period, scope, page }) → { scope, payload: [linhas], meta: { page, per_page, total } }
// resend(inviteId) → { payload: { id, resent_at } }
class CrmBookingStatsAPI extends ApiClient {
  constructor() {
    super('crm/booking_stats', { accountScoped: true });
  }

  show({ period, scope } = {}) {
    return axios.get(this.url, { params: { period, scope } });
  }

  openedNotBooked({ period, scope, page = 1 } = {}) {
    return axios.get(`${this.url}/opened_not_booked`, {
      params: { period, scope, page },
    });
  }

  resend(inviteId) {
    return axios.post(`${this.url}/opened_not_booked/${inviteId}/resend`);
  }
}

export default new CrmBookingStatsAPI();
