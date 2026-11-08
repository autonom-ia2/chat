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
  // ownerId (#2694): com quem ficam os cards; sem ele, com quem manda.
  createCrmCards({ leadIds, pipelineId, stageId, ownerId = null }) {
    return axios.post(`${this.url}/leads/crm_cards`, {
      lead_ids: leadIds,
      pipeline_id: pipelineId,
      stage_id: stageId,
      ...(ownerId ? { owner_id: ownerId } : {}),
    });
  }

  // Quem pode receber o card no funil (#2694): só para quem gere funis.
  getCrmOwners(pipelineId) {
    return axios.get(`${this.url}/leads/crm_owners`, {
      params: { pipeline_id: pipelineId },
    });
  }

  // Criar contatos em lote (#732): até 30 leads por pedido, o mesmo contato
  // de POST leads/:id/contact, com resultado por lead (created, existing,
  // failed).
  createLeadContacts(leadIds) {
    return axios.post(`${this.url}/leads/contacts`, { lead_ids: leadIds });
  }

  // Descartar com motivo (#732), um lead ou a seleção. Devolve os leads.
  // "Guardar para mandar mensagem" (#2695): os leads viram um Público de
  // Campanhas. Volta o Público e quem ficou de fora, com o motivo.
  createAudience({ leadIds, name }) {
    return axios.post(`${this.url}/leads/audience`, {
      lead_ids: leadIds,
      name,
    });
  }

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

  // "Não quer ser contatado" (chat#713): a recusa fica no lead, separada do
  // status, e vai para os contatos que o número ou o e-mail alcançam.
  refuseLeadConsent(leadId) {
    return axios.post(`${this.url}/leads/${leadId}/consent_refusal`);
  }

  withdrawLeadConsentRefusal(leadId) {
    return axios.delete(`${this.url}/leads/${leadId}/consent_refusal`);
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
