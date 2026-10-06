/* global axios */
// Calls of the new campaign journey (#993). Audience endpoints live under campaign_imports
// (contracts in docs/campaigns/publicos/api-992.md and api-1005.md); campaign creation is
// api-1005.md §4; the rest of what the screen reads is in api-993-frontend-needs.md.
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

  // Side panel "Ver contatos e empresas" (#993).
  contacts(id, page = 1) {
    return axios.get(`${this.url}/${id}/contacts`, { params: { page } });
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

export const audiencesAPI = new AudiencesAPI();
// POST /campaign_journey/campaigns (api-1005.md §4, api-999.md §2). `create` sends JSON;
// `createWithFile` sends multipart with campaign[...] fields (WhatsApp API attachment).
const campaignsClient = new ApiClient('campaign_journey/campaigns', {
  accountScoped: true,
});
const previewsClient = new ApiClient('campaign_journey/recipient_previews', {
  accountScoped: true,
});

const appendCampaignField = (formData, key, value) => {
  if (value === null || value === undefined) return;
  if (value instanceof File) {
    formData.append(`campaign[${key}]`, value);
    return;
  }
  if (typeof value === 'object') {
    Object.entries(value).forEach(([inner, innerValue]) =>
      formData.append(`campaign[${key}][${inner}]`, innerValue)
    );
    return;
  }
  formData.append(`campaign[${key}]`, value);
};

export const journeyCampaignsAPI = {
  create: payload => campaignsClient.create(payload),
  createWithFile: ({ campaign, ...rest }) => {
    const formData = new FormData();
    Object.entries(rest).forEach(([key, value]) => formData.append(key, value));
    Object.entries(campaign).forEach(([key, value]) =>
      appendCampaignField(formData, key, value)
    );
    return axios.post(campaignsClient.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  // "Vão receber" before creating (exact, each person once).
  preview: payload => previewsClient.create(payload),
};
