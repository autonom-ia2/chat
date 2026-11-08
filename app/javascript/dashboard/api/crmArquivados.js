/* global axios */
import ApiClient from './ApiClient';

// Arquivados, restaurar e arquivar funil (#2095, PR #2097). Arquivo próprio para não disputar o crmKanban.js.
class CrmArquivadosAPI extends ApiClient {
  constructor() {
    super('crm', { accountScoped: true });
  }

  // GET /crm/cards/archived — { pipeline_id?, search?, page, per_page }. Sem pipeline_id: todos os funis,
  // inclusive os cards guardados em funil arquivado.
  listar(params = {}) {
    return axios.get(`${this.url}/cards/archived`, { params });
  }

  // POST /crm/cards/:id/restore — 409 crm.card_restore_conflict traz o card aberto do mesmo cliente.
  restaurar(id, { force = false } = {}) {
    return axios.post(`${this.url}/cards/${id}/restore`, { force });
  }

  // POST /crm/cards/restore — tudo ou nada; os pulados voltam em `skipped` com o motivo.
  restaurarVarios(ids, { force = false } = {}) {
    return axios.post(`${this.url}/cards/restore`, { ids, force });
  }

  funisArquivados() {
    return axios.get(`${this.url}/pipelines`, {
      params: { status: 'archived' },
    });
  }

  restaurarFunil(id) {
    return axios.post(`${this.url}/pipelines/${id}/restore`);
  }

  previaDoArquivarFunil(id) {
    return axios.get(`${this.url}/pipelines/${id}/archive_preview`);
  }

  // DELETE /crm/pipelines/:id — move_to_stage_id (cards abertos), inboxes_to_pipeline_id (caixas) e
  // new_default_pipeline_id (novo principal), tudo numa transação.
  arquivarFunil(id, params = {}) {
    return axios.delete(`${this.url}/pipelines/${id}`, { params });
  }
}

export default new CrmArquivadosAPI();
