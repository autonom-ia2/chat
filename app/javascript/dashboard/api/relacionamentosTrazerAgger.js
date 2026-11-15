/* global axios */
import ApiClient from './ApiClient';

// #2900 (E7.3) — "Trazer do Agger" (relacionamentos/trazer/seguros…): começar
// a busca, buscar de novo, as buscas já feitas e o interruptor "Buscar novos
// seguros todo dia". O Conferir, trazer, o andamento e o desfazer de uma busca
// são as rotas das leituras, as mesmas dos PDFs (api/relacionamentosTrazerPdfs.js).
// Quem dá nome às recusas é fonte/trazerAggerFonte.js.
class RelacionamentosTrazerAggerAPI extends ApiClient {
  constructor() {
    super('relacionamentos/trazer/seguros', { accountScoped: true });
  }

  // → { leituraId }. Enquanto uma busca da conta anda, devolve a mesma.
  buscar() {
    return axios.post(`${this.url}/busca`);
  }

  // A busca parada continua; a que terminou pede o mesmo período de novo.
  deNovo(id) {
    return axios.post(`${this.url}/leituras/${id}/de_novo`);
  }

  historico() {
    return axios.get(`${this.url}/leituras`, {
      params: { origem: 'conector' },
    });
  }

  buscaDiaria() {
    return axios.get(`${this.url}/busca_diaria`);
  }

  mudarBuscaDiaria(ligado) {
    return axios.put(`${this.url}/busca_diaria`, { ligado });
  }
}

export default new RelacionamentosTrazerAggerAPI();
