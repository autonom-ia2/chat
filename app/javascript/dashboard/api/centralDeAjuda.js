/* global axios */
import ApiClient from './ApiClient';

// Leitura da Central de Ajuda da plataforma (#501). O `ref` do artigo é o id com hífen: 02.06 → 02-06.
class CentralDeAjudaAPI extends ApiClient {
  constructor() {
    super('central-de-ajuda', { accountScoped: true });
  }

  artigo(ref) {
    return axios.get(`${this.url}/${encodeURIComponent(ref)}`);
  }

  buscar(termo) {
    return axios.get(`${this.url}/busca`, { params: { termo } });
  }

  // O Jev escolhe o artigo que melhor responde ao que a pessoa escreveu (#977).
  // Volta { melhor: artigo | null, certeza: número | null }.
  buscarInteligente(termo) {
    return axios.get(`${this.url}/busca_inteligente`, { params: { termo } });
  }
}

export default new CentralDeAjudaAPI();
