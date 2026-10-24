/* global axios */
import ApiClient from './ApiClient';

// Excluir de vez (#2096, PR #2098): cards arquivados, funil arquivado e os cards ao excluir um contato. Só o
// administrador. Arquivo próprio para não disputar o crmKanban.js nem o crmArquivados.js do #2097.
class CrmExcluirAPI extends ApiClient {
  constructor() {
    super('crm', { accountScoped: true });
  }

  // POST /crm/cards/permanent_delete — só cards já arquivados; `confirmation` é a palavra digitada.
  excluirCards(ids, confirmation) {
    return axios.post(`${this.url}/cards/permanent_delete`, {
      card_ids: ids,
      confirmation,
    });
  }

  // GET /crm/pipelines/:id/permanent_delete_preview — contagens, vendas e reuniões futuras do funil.
  previaDoFunil(id) {
    return axios.get(`${this.url}/pipelines/${id}/permanent_delete_preview`);
  }

  // POST /crm/pipelines/:id/permanent_delete — `confirmation` é o nome do funil; com cards, `cards` é 'move'
  // (com target_stage_id) ou 'delete'. Com cards, roda em segundo plano (202).
  excluirFunil(id, { confirmation, cards, targetStageId } = {}) {
    return axios.post(`${this.url}/pipelines/${id}/permanent_delete`, {
      confirmation,
      cards,
      target_stage_id: targetStageId,
    });
  }

  // GET /crm/contacts/:id/permanent_delete_preview — os cards do contato, com funil, etapa, valor e reunião.
  previaDoContato(contactId) {
    return axios.get(
      `${this.url}/contacts/${contactId}/permanent_delete_preview`
    );
  }

  // POST /crm/contacts/:id/permanent_delete — `cards` é 'delete' (apagar de vez) ou 'keep' (sem dado pessoal).
  excluirContato(contactId, { confirmation, cards }) {
    return axios.post(`${this.url}/contacts/${contactId}/permanent_delete`, {
      confirmation,
      cards,
    });
  }
}

export default new CrmExcluirAPI();
