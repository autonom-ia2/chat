/* global axios */
import ApiClient from './ApiClient';

// #2894 — as leituras da Lista nova de Relacionamentos (GET relacionamentos/…).
// Os params vão como o servidor espera (grupo, busca, ordem, pagina e, só em
// Pessoas, filtros[…]): quem traduz o pedido da tela é fonte/listaFonte.js.
// Pedido que o servidor não conhece responde 422; Empresas sem a chave
// `companies` responde 403.
class RelacionamentosAPI extends ApiClient {
  constructor() {
    super('relacionamentos', { accountScoped: true });
  }

  pessoas(params) {
    return axios.get(`${this.url}/pessoas`, { params });
  }

  contagensDePessoas(params) {
    return axios.get(`${this.url}/pessoas/contagens`, { params });
  }

  todasAsPessoas(params) {
    return axios.get(`${this.url}/pessoas/todas`, { params });
  }

  empresas(params) {
    return axios.get(`${this.url}/empresas`, { params });
  }

  contagensDeEmpresas(params) {
    return axios.get(`${this.url}/empresas/contagens`, { params });
  }

  resumo() {
    return axios.get(`${this.url}/resumo`);
  }

  opcoesDeFiltro() {
    return axios.get(`${this.url}/opcoes_de_filtro`);
  }
}

export default new RelacionamentosAPI();
