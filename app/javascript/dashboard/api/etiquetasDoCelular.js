/* global axios */
// Etiquetas do WhatsApp do celular (#1823, F1b): Api::V1::Accounts::EtiquetasDoCelularController.
//   GET /etiquetas_do_celular → { payload: [{ label_id, inbox_id, caixa,
//        nome_no_celular, color_index, criada_pelo_celular }] }
// Sem a flag `etiquetas_do_celular` na conta, responde 404.
import ApiClient from './ApiClient';

class EtiquetasDoCelularAPI extends ApiClient {
  constructor() {
    super('etiquetas_do_celular', { accountScoped: true });
  }

  listar() {
    return axios.get(this.url);
  }
}

export default new EtiquetasDoCelularAPI();
