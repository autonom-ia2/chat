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
}

export default new AutomacoesAPI();
