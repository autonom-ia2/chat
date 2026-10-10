/* global axios */
import ApiClient from './ApiClient';

// Meus horários (#1195, J8-A11): /api/v1/accounts/:accountId/crm/my_booking_hours.
// Só a própria pessoa: não há parâmetro de quem.
class CrmMyBookingHoursAPI extends ApiClient {
  constructor() {
    super('crm/my_booking_hours', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  save({ weekdays, startHour, endHour }) {
    return axios.put(this.url, {
      working_hours: {
        weekdays,
        start_hour: startHour,
        end_hour: endHour,
      },
    });
  }

  usePageHours() {
    return axios.put(this.url, { use_page_hours: true });
  }

  setPaused(paused) {
    return axios.put(this.url, { paused });
  }
}

export default new CrmMyBookingHoursAPI();
