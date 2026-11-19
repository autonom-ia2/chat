/* global axios */
// #3071 — pôr ou tirar etiquetas do contato uma a uma (contacts/:id/labels/
// alterar, AlterarEtiquetasConcern, #2461). A rota de sempre (labels#create)
// troca a lista inteira, e quem gravava por último apagava a etiqueta posta por
// outra janela, aba, pessoa ou automação. Responde `{ payload: [lista final] }`.
import ApiClient from './ApiClient';
import { TEMPO_MAXIMO_MS } from './etiquetasDaConversa';

class EtiquetasDoContatoAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  alterar(contatoId, { por = [], tirar = [] }) {
    return axios.patch(
      `${this.url}/${contatoId}/labels/alterar`,
      { por, tirar },
      { timeout: TEMPO_MAXIMO_MS }
    );
  }
}

export default new EtiquetasDoContatoAPI();
