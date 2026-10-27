/* global axios */
import ApiClient from './ApiClient';

// #2211 — a busca dentro da lista de conversas: conversas (uma por pessoa), mensagens e pessoas sem
// conversa num pedido só (GET /busca_da_lista).
class BuscaDaListaAPI extends ApiClient {
  constructor() {
    super('busca_da_lista', { accountScoped: true });
  }

  buscar(q, { signal } = {}) {
    return axios.get(this.url, { params: { q }, signal });
  }
}

export default new BuscaDaListaAPI();
