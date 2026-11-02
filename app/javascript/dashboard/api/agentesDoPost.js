/* global axios */
import ApiClient from './ApiClient';

// Os comentários do post em Agentes (#2469, PR 3a do #2436): o cuidado de cada
// post ou anúncio, no Instagram e no Facebook, como cartão
// (AgentesDoPostController).
//
// - list: { cuidados: [{ id, kind, target_id, perfil, network, status }] }, só
//   do banco.
// - get: o item mais { legenda, capa, foto, nota, can_manage, portas[], comentarios },
//   lido na Meta na hora, sem IA.
// - estado: 'on' | 'paused' → o mesmo do get.
// - testar: { pergunta, formato: 'publico' | 'privado', network } →
//   { status: 'escrito', texto } | { status: 'fica_com_o_dono', motivo } |
//   { status: 'frases_fixas', motivo } | { status: 'no_private' }; no escrito, `material`: os
//   arquivos só deste post de que a resposta saiu (#2487).
// - materiais / anexar / tirar (#2487): o material só deste post ou anúncio,
//   { materiais: [{ id, reference, source_type, status, agente, review }] }.
class AgentesDoPostAPI extends ApiClient {
  constructor() {
    super('agentes_do_post', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  get(id) {
    return axios.get(`${this.url}/${id}`);
  }

  estado(id, status) {
    return axios.put(`${this.url}/${id}/estado`, { status });
  }

  testar(id, { pergunta, formato, network }) {
    return axios.post(`${this.url}/${id}/testar`, {
      pergunta,
      formato,
      network,
    });
  }

  materiais(id) {
    return axios.get(`${this.url}/${id}/materiais`);
  }

  anexar(id, arquivo) {
    const corpo = new FormData();
    corpo.append('file', arquivo);
    return axios.post(`${this.url}/${id}/materiais`, corpo);
  }

  tirar(id, materialId) {
    return axios.delete(`${this.url}/${id}/materiais/${materialId}`);
  }
}

export default new AgentesDoPostAPI();
