/* global axios */
import ApiClient from './ApiClient';

// #2894 — as leituras da Lista nova de Relacionamentos (GET relacionamentos/…).
// Os params vão como o servidor espera (grupo, busca, ordem, pagina e, só em
// Pessoas, filtros[…]): quem traduz o pedido da tela é fonte/listaFonte.js.
// Pedido que o servidor não conhece responde 422; Empresas sem a chave
// `companies` responde 403.
//
// As ações em grupo (funis, criar cards, etiquetar, apagar) vão com o corpo
// que fonte/acoesDaListaFonte.js monta: `pessoa_ids` e o que a ação pede. Chave
// que o servidor não conhece responde 422.
//
// #3062 — "Baixar planilha" (POST pessoas/exportar) vai com os mesmos params da
// lista, na URL; "Tirar etiquetas" (POST etiqueta/tirar), com o corpo de pôr.
//
// #2895 — as leituras da ficha, pelo id da pessoa ou da empresa. A resposta já
// vem no formato que a tela mostra; 404 é quem não existe e 401/403, quem não
// pode ver (fonte/fichaFonte.js dá nome a esses erros).
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

  exportarPessoas(params) {
    return axios.post(`${this.url}/pessoas/exportar`, null, { params });
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

  funis() {
    return axios.get(`${this.url}/funis`);
  }

  criarCards(corpo) {
    return axios.post(`${this.url}/cards`, corpo);
  }

  aplicarEtiqueta(corpo) {
    return axios.post(`${this.url}/etiqueta`, corpo);
  }

  tirarEtiqueta(corpo) {
    return axios.post(`${this.url}/etiqueta/tirar`, corpo);
  }

  apagar(corpo) {
    return axios.post(`${this.url}/apagar`, corpo);
  }

  pessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}`);
  }

  conversasDaPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/conversas`);
  }

  cardsDaPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/cards`);
  }

  // #3097 — as faixas dos grupos de compra da conta.
  faixasDeCompra() {
    return axios.get(`${this.url}/grupos_de_compra`);
  }

  salvarFaixasDeCompra(faixas) {
    return axios.patch(`${this.url}/grupos_de_compra`, { faixas });
  }

  // #3097 — o resumo das compras da pessoa (cards ganhos nos funis de Vender).
  comprasDaPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/compras`);
  }

  // #3100 — o cartão fidelidade da pessoa: o cartão da conta, o saldo, o que
  // vence, os últimos movimentos e os cupons; o histórico por página (20);
  // dar o prêmio (com a chave de idempotência: o mesmo toque repetido não tira
  // a meta duas vezes).
  fidelidadeDaPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/fidelidade`);
  }

  movimentosDaPessoa(id, pagina) {
    return axios.get(`${this.url}/pessoas/${id}/fidelidade/movimentos`, {
      params: { pagina },
    });
  }

  darPremio(id, chave) {
    return axios.post(`${this.url}/pessoas/${id}/fidelidade/premios`, null, {
      headers: { 'Idempotency-Key': chave },
    });
  }

  notasDaPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/notas`);
  }

  arquivosDaPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/arquivos`);
  }

  origemDaPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/origem`);
  }

  empresa(id) {
    return axios.get(`${this.url}/empresas/${id}`);
  }

  pessoasDaEmpresa(id) {
    return axios.get(`${this.url}/empresas/${id}/pessoas`);
  }

  conversasDaEmpresa(id) {
    return axios.get(`${this.url}/empresas/${id}/conversas`);
  }

  cardsDaEmpresa(id) {
    return axios.get(`${this.url}/empresas/${id}/cards`);
  }
}

export default new RelacionamentosAPI();
