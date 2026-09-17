/* global axios */
import ApiClient from './ApiClient';

class EmailCampaignReportsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/reports', { accountScoped: true });
  }

  getReports(campaignId, { campaignStatus, signal } = {}) {
    return axios.get(this.url, {
      params: {
        campaign_id: campaignId || undefined,
        campaign_status: campaignStatus || undefined,
      },
      signal,
    });
  }

  getCampaignDetail(id) {
    return axios.get(`${this.url}/${id}`);
  }

  getClicks(id, { signal } = {}) {
    return axios.get(`${this.url}/${id}/clicks`, { signal });
  }

  getTimeline(id, interval = 'day', { signal } = {}) {
    return axios.get(`${this.url}/${id}/timeline`, {
      params: { interval },
      signal,
    });
  }

  getRecipients(id, { page = 1, search = '', status, problem, signal } = {}) {
    return axios.get(`${this.url}/${id}/recipients`, {
      params: {
        page,
        q: search,
        status: status || undefined,
        problem: problem || undefined,
      },
      signal,
    });
  }

  export(id, { search = '', status, problem } = {}) {
    return axios.get(`${this.url}/${id}/export`, {
      params: {
        q: search,
        status: status || undefined,
        problem: problem || undefined,
      },
      responseType: 'blob',
    });
  }

  getImportIssues(id, { page = 1, signal } = {}) {
    return axios.get(`${this.url}/${id}/import_issues`, {
      params: { page },
      signal,
    });
  }

  exportImportIssues(id) {
    return axios.get(`${this.url}/${id}/import_issues/export`, {
      responseType: 'blob',
    });
  }
}

export default new EmailCampaignReportsAPI();
