/* global axios */
import ApiClient from './ApiClient';

class AutonomiaProspectingAPI extends ApiClient {
  constructor() {
    super('autonomia/prospecting', { accountScoped: true });
  }

  getSearches(params = {}) {
    return axios.get(`${this.url}/searches`, { params });
  }

  getSearch(searchId) {
    return axios.get(`${this.url}/searches/${searchId}`);
  }

  getLocationSuggestions(query) {
    return axios.get(`${this.url}/searches/location_suggestions`, {
      params: { query },
    });
  }

  getLocationDetails(placeId) {
    return axios.get(`${this.url}/searches/location_details`, {
      params: { place_id: placeId },
    });
  }

  createSearch(search) {
    return axios.post(`${this.url}/searches`, { search });
  }

  updateSearch(searchId, search) {
    return axios.patch(`${this.url}/searches/${searchId}`, { search });
  }

  deleteSearch(searchId) {
    return axios.delete(`${this.url}/searches/${searchId}`);
  }

  // Exportação pelo servidor (#682): format é csv ou xlsx; leadIds, opcional,
  // limita aos leads da tela (seleção ou filtro), na ordem dela.
  exportSearch(searchId, { format, leadIds } = {}) {
    return axios.get(`${this.url}/searches/${searchId}/export`, {
      params: { format, lead_ids: leadIds },
      responseType: 'blob',
    });
  }

  exportList(listId, { format, leadIds } = {}) {
    return axios.get(`${this.url}/lists/${listId}/export`, {
      params: { format, lead_ids: leadIds },
      responseType: 'blob',
    });
  }

  getLeads(params = {}) {
    return axios.get(`${this.url}/leads`, { params });
  }

  createLeadContact(leadId) {
    return axios.post(`${this.url}/leads/${leadId}/contact`);
  }

  // Envio ao CRM (#680): até 30 leads por pedido, resultado por lead
  // (created, existing, failed). Um lead só também vai por aqui.
  createCrmCards({ leadIds, pipelineId, stageId }) {
    return axios.post(`${this.url}/leads/crm_cards`, {
      lead_ids: leadIds,
      pipeline_id: pipelineId,
      stage_id: stageId,
    });
  }

  // Campanha a partir da seleção da busca (#680): devolve o segmento, com o
  // motivo de cada lead bloqueado.
  // campaignType: 'whatsapp_api' ou 'one_off' (#732); sem ele, envio único.
  addLeadsToCampaign({ leadIds, campaignId, campaignType, segmentName }) {
    return axios.post(`${this.url}/leads/campaign_segment`, {
      lead_ids: leadIds,
      campaign_id: campaignId,
      campaign_type: campaignType,
      segment_name: segmentName,
    });
  }

  // Criar contatos em lote (#732): até 30 leads por pedido, o mesmo contato
  // de POST leads/:id/contact, com resultado por lead (created, existing,
  // failed).
  createLeadContacts(leadIds) {
    return axios.post(`${this.url}/leads/contacts`, { lead_ids: leadIds });
  }

  // Descartar com motivo (#732), um lead ou a seleção. Devolve os leads.
  discardLeads({ leadIds, reason }) {
    return axios.post(`${this.url}/leads/discard`, {
      lead_ids: leadIds,
      reason,
    });
  }

  // Um dos sócios da pesquisa vira o decisor e o contato do lead (#680).
  adoptOwner(leadId, ownerName) {
    return axios.post(`${this.url}/leads/${leadId}/adopt_owner`, {
      owner_name: ownerName,
    });
  }

  verifyLeadWhatsApp(leadId) {
    return axios.post(`${this.url}/leads/${leadId}/whatsapp_verification`);
  }

  enrichLead(leadId) {
    return axios.post(`${this.url}/leads/${leadId}/enrichment`);
  }

  // Pesquisa de empresa e decisor (#679): 202 e fila; force ignora o resultado
  // guardado (verificar novamente).
  researchLead(leadId, { force = false } = {}) {
    return axios.post(`${this.url}/leads/${leadId}/research`, { force });
  }

  updateLead(leadId, lead) {
    return axios.patch(`${this.url}/leads/${leadId}`, { lead });
  }

  getLists() {
    return axios.get(`${this.url}/lists`);
  }

  getList(listId) {
    return axios.get(`${this.url}/lists/${listId}`);
  }

  createList(list) {
    return axios.post(`${this.url}/lists`, { list });
  }

  addLeadToList(listId, leadId) {
    return axios.post(`${this.url}/lists/${listId}/leads`, { lead_id: leadId });
  }

  removeLeadFromList(listId, leadId) {
    return axios.delete(`${this.url}/lists/${listId}/leads/${leadId}`);
  }

  createCampaignSegment(listId, campaignSegment = {}) {
    return axios.post(`${this.url}/lists/${listId}/campaign_segment`, {
      campaign_segment: campaignSegment,
    });
  }

  getSettings() {
    return axios.get(`${this.url}/settings`);
  }

  updateSettings(settings) {
    return axios.patch(`${this.url}/settings`, { settings });
  }

  // Jogadas salvas da conta (#732). A lista vem em getSettings (saved_presets).
  createSavedPreset(savedPreset) {
    return axios.post(`${this.url}/saved_presets`, {
      saved_preset: savedPreset,
    });
  }

  updateSavedPreset(savedPresetId, savedPreset) {
    return axios.patch(`${this.url}/saved_presets/${savedPresetId}`, {
      saved_preset: savedPreset,
    });
  }

  deleteSavedPreset(savedPresetId) {
    return axios.delete(`${this.url}/saved_presets/${savedPresetId}`);
  }
}

export default new AutonomiaProspectingAPI();
