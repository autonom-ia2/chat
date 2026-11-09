/* global axios */
import ApiClient from '../ApiClient';

// #2414 F5 — a Automação livre pelo editor. Salvar e ligar levam a versão que a
// tela mostrou: se outra pessoa salvou no meio, a API responde 409.
class AutomacoesAPI extends ApiClient {
  constructor() {
    super('autonomia/automacoes', { accountScoped: true });
  }

  // O catálogo de passos (lib/operator_guide/automacao-passos.json).
  passos() {
    return axios.get(`${this.url}/passos`);
  }

  salvar(id, { receita, baseVersaoId }) {
    return axios.patch(`${this.url}/${id}`, {
      receita,
      base_versao_id: baseVersaoId,
    });
  }

  renomear(id, nome) {
    return axios.patch(`${this.url}/${id}`, { nome });
  }

  ligar(id, versaoId) {
    return axios.post(`${this.url}/${id}/ligar`, { versao_id: versaoId });
  }

  desligar(id) {
    return axios.post(`${this.url}/${id}/desligar`);
  }

  // "O que aconteceu" (#2498): 20 execuções por página, a mais nova primeiro.
  historico(id, pagina = 1) {
    return axios.get(`${this.url}/${id}/historico`, { params: { pagina } });
  }

  // Ensaiar (#2498): só lê. Sem id é a automação ainda não salva; `receita`
  // é o rascunho da tela; `conversaId`, o número da conversa escolhida.
  ensaiar(id, { receita, conversaId } = {}) {
    const caminho = id ? `${this.url}/${id}/ensaio` : `${this.url}/ensaio`;
    return axios.post(caminho, { receita, conversa_id: conversaId });
  }

  // "Testar este passo" (#2500 C2): uma conversa por pedido. O 1º escolhe as
  // candidatas (o servidor devolve os ids); os seguintes mandam `conversaId`,
  // conferido no servidor. Chama a IA e paga.
  testarPasso({ receita, passoId, conversaId }) {
    return axios.post(`${this.url}/testar_passo`, {
      receita,
      passo_id: passoId,
      conversa_id: conversaId,
    });
  }

  // O custo da IA nos últimos 30 dias: a soma de cada automação (lista) e a
  // média de cada passo (cartão). Sem financial_view, `com_valores` é false.
  custos() {
    return axios.get(`${this.url}/custos`);
  }

  custosDaAutomacao(id) {
    return axios.get(`${this.url}/${id}/custos`);
  }

  // G15: as agentes de IA que podem receber conversa na conta (id e nome).
  agentesDeIa() {
    return axios.get(`${this.url}/agentes_de_ia`);
  }
}

export default new AutomacoesAPI();
