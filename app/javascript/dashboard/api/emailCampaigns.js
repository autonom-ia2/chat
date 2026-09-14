/* global axios */
import ApiClient from './ApiClient';

class EmailCampaignsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/campaigns', { accountScoped: true });
  }

  sendNow(id) {
    return axios.post(`${this.url}/${id}/send_now`);
  }

  schedule(id, scheduledAt) {
    return axios.post(`${this.url}/${id}/schedule`, {
      scheduled_at: scheduledAt,
    });
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  getRecipients(id, page = 1) {
    return axios.get(`${this.url}/${id}/recipients?page=${page}`);
  }

  sendTest(id, toEmail) {
    return axios.post(`${this.url}/${id}/test_send`, { to_email: toEmail });
  }

  placeholders(id) {
    return axios.get(`${this.url}/${id}/placeholders`);
  }

  validate(id) {
    return axios.get(`${this.url}/${id}/validate`);
  }

  retryImport(id) {
    return axios.post(`${this.url}/${id}/recipients/retry_import`);
  }

  importRecipients(id, file) {
    const formData = new FormData();
    formData.append('import_file', file);
    return axios.post(`${this.url}/${id}/recipients`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new EmailCampaignsAPI();
