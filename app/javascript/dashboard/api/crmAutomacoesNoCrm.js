/* global axios */
import ApiClient from './ApiClient';

// #2499 F6.3/F6.5 — as automações do motor novo no card e na etapa do funil. Ligar e desligar cada uma é o da própria
// automação (api/autonomia/automacoes.js). Arquivo próprio para não disputar o crmKanban.js.
class CrmAutomacoesNoCrmAPI extends ApiClient {
  constructor() {
    super('crm', { accountScoped: true });
  }

  // GET /crm/cards/:id/automacoes — { automacoes: [{ id, automacao_id, nome, estado, passo, comecou, receita,
  // esperando_ate, esperando_sem_prazo, feitos: [{ passo, em }] }] }. Só card aberto tem automação rodando.
  doCard(cardId) {
    return axios.get(`${this.url}/cards/${cardId}/automacoes`);
  }

  // POST /crm/cards/:id/automacoes/:automacao_id/parar — { paradas }. Só neste card; os outros seguem.
  pararNoCard(cardId, automacaoId) {
    return axios.post(
      `${this.url}/cards/${cardId}/automacoes/${automacaoId}/parar`
    );
  }

  // GET /crm/stages/:id/automacoes — { automacoes: [{ id, nome, ativa, versao: { id, receita } }] }.
  daEtapa(etapaId) {
    return axios.get(`${this.url}/stages/${etapaId}/automacoes`);
  }
}

export default new CrmAutomacoesNoCrmAPI();
