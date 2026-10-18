/* global axios */
// Nome livre das etiquetas (#1823, F1a): Api::V1::Accounts::NomesDeEtiquetasController.
//   GET    /nomes_de_etiquetas            → { payload: [{ label_id, nome }] }
//   PUT    /nomes_de_etiquetas/:label_id  { nome } → { payload: { label_id, nome } }
//   DELETE /nomes_de_etiquetas/:label_id  → 204
// Sem a flag `etiquetas_do_whatsapp` na conta, as três respondem 404.
import ApiClient from './ApiClient';

class NomesDeEtiquetasAPI extends ApiClient {
  constructor() {
    super('nomes_de_etiquetas', { accountScoped: true });
  }

  listar() {
    return axios.get(this.url);
  }

  gravar(labelId, nome) {
    return axios.put(`${this.url}/${labelId}`, { nome });
  }

  apagar(labelId) {
    return axios.delete(`${this.url}/${labelId}`);
  }
}

export default new NomesDeEtiquetasAPI();
