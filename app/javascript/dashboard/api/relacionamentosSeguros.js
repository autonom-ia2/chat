/* global axios */
import ApiClient from './ApiClient';

// #2897 — a carteira de seguros de Relacionamentos (relacionamentos/seguros…):
// a aba Seguros, a gaveta de um seguro com as escritas dela, o PDF e os seguros
// da ficha da pessoa e da empresa. Só existe em conta de seguros (o payload da
// conta diz `carteira_seguros`): fora dela toda rota responde 404.
//
// Os params e o corpo vão como o servidor espera; quem traduz o que a tela pede
// (datas, filtros) e dá nome às recusas é fonte/carteiraFonteReal.js. Pedido de
// lista que o servidor não conhece e escrita recusada respondem 422 com
// `{ error: "<código>" }`; 401 e 403 são de quem não pode ver ou editar a pessoa.
class RelacionamentosSegurosAPI extends ApiClient {
  constructor() {
    super('relacionamentos', { accountScoped: true });
  }

  lista(params) {
    return axios.get(`${this.url}/seguros`, { params });
  }

  contagens(params) {
    return axios.get(`${this.url}/seguros/contagens`, { params });
  }

  resumo() {
    return axios.get(`${this.url}/seguros/resumo`);
  }

  opcoesDeFiltro() {
    return axios.get(`${this.url}/seguros/opcoes_de_filtro`);
  }

  seguro(id) {
    return axios.get(`${this.url}/seguros/${id}`);
  }

  historia(id) {
    return axios.get(`${this.url}/seguros/${id}/historia`);
  }

  daPessoa(id) {
    return axios.get(`${this.url}/pessoas/${id}/seguros`);
  }

  // Só no Enterprise, com Empresas ligada na conta.
  daEmpresa(id) {
    return axios.get(`${this.url}/empresas/${id}/seguros`);
  }

  // `dados`: só os campos que mudaram.
  corrigir(id, dados) {
    return axios.patch(`${this.url}/seguros/${id}`, dados);
  }

  cancelar(id) {
    return axios.post(`${this.url}/seguros/${id}/cancelar`);
  }

  voltarAAtivo(id) {
    return axios.post(`${this.url}/seguros/${id}/voltar_a_ativo`);
  }

  // Devolve `{ url }`: um link que vale um minuto. Pedir na hora de abrir.
  linkDoPdf(id) {
    return axios.get(`${this.url}/seguros/${id}/pdf`);
  }

  guardarPdf(id, arquivo) {
    const corpo = new FormData();
    corpo.append('arquivo', arquivo);
    return axios.post(`${this.url}/seguros/${id}/pdf`, corpo, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  tirarPdf(id) {
    return axios.delete(`${this.url}/seguros/${id}/pdf`);
  }
}

export default new RelacionamentosSegurosAPI();
