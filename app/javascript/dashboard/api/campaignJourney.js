/* global axios */
// Calls of the new campaign journey (#993). Audience endpoints live under campaign_imports
// (contracts in docs/campaigns/publicos/api-992.md and api-1005.md); campaign creation is
// api-1005.md §4. The two calls the backend still lacks (problem_rows, sample_contact) are
// in docs/campaigns/publicos/api-993-frontend-needs.md; without them the screen degrades.
import ApiClient from './ApiClient';

class AudiencesAPI extends ApiClient {
  constructor() {
    super('campaign_imports', { accountScoped: true });
  }

  // Saved audiences with search on the server (Passo 1 of Nova campanha).
  list({ saved = true, q = '', page = 1 } = {}) {
    return axios.get(this.url, { params: { saved, q, page } });
  }

  createAudience({ name, file }) {
    const formData = new FormData();
    formData.append('name', name);
    formData.append('import_file', file);
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  chooseColumns(id, mapping) {
    return axios.patch(`${this.url}/${id}/columns`, mapping);
  }

  // { email: true|false, whatsapp: true|false } (api-1005.md §5)
  setChannels(id, channels) {
    return axios.patch(`${this.url}/${id}/channels`, channels);
  }

  // "Criar e ligar" (api-992.md §9)
  setCreateCompanies(id, createCompanies) {
    return axios.patch(`${this.url}/${id}/companies`, {
      create_companies: createCompanies,
    });
  }

  problemRows(id, page = 1) {
    return axios.get(`${this.url}/${id}/problem_rows`, { params: { page } });
  }

  sampleContact(id) {
    return axios.get(`${this.url}/${id}/sample_contact`);
  }

  // Rails reads `variables[][key]=1&variables[][label]=nome` as an array of hashes.
  variableSuggestions(id, variables) {
    const query = new URLSearchParams();
    variables.forEach(({ key, label }) => {
      query.append('variables[][key]', key);
      query.append('variables[][label]', label);
    });
    return axios.get(
      `${this.url}/${id}/variable_suggestions?${query.toString()}`
    );
  }

  variableCoverage(id, { mapping, defaults }) {
    return axios.post(`${this.url}/${id}/variable_coverage`, {
      mapping,
      defaults,
    });
  }

  confirm(id) {
    return axios.post(`${this.url}/${id}/confirm`);
  }

  downloadErrors(id) {
    return axios.get(`${this.url}/${id}/download?file=error_csv`, {
      responseType: 'blob',
    });
  }
}

// Campaign journey reads (#1002):
// GET .../campaign_journey/contact_origins/:contactId
//   → { payload: { marks: [{ source, source_id, headline, touched_at, ... }], audiences: [{ id, name }] } }
// GET .../campaign_journey/campaign_names?campaign_ids=1,2&whatsapp_api_campaign_ids=3
//   → { payload: { campaigns: { id: title }, whatsapp_api_campaigns: { id: title } } }
class CampaignJourneyAPI extends ApiClient {
  constructor() {
    super('campaign_journey', { accountScoped: true });
  }

  getContactOrigins(contactId) {
    return axios.get(`${this.url}/contact_origins/${contactId}`);
  }

  getCampaignNames({ campaignIds = [], whatsappApiCampaignIds = [] }) {
    return axios.get(`${this.url}/campaign_names`, {
      params: {
        campaign_ids: campaignIds.join(','),
        whatsapp_api_campaign_ids: whatsappApiCampaignIds.join(','),
      },
    });
  }
}

export const audiencesAPI = new AudiencesAPI();
// POST /campaign_journey/campaigns (api-1005.md §4): only `create` is used.
export const journeyCampaignsAPI = new ApiClient('campaign_journey/campaigns', {
  accountScoped: true,
});
export default new CampaignJourneyAPI();
