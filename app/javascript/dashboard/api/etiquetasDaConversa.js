/* global axios */
// #2202 (PR 3) — pôr ou tirar etiquetas da conversa uma a uma (labels/alterar).
// A rota de sempre (labels#create) troca a lista inteira, e quem gravava por
// último apagava a etiqueta posta por outra janela, aba ou pessoa. Responde
// `{ payload: [lista final] }`, no formato do create.
import ApiClient from './ApiClient';

// Sem resposta nesse tempo, a chamada falha e a tela volta ao que está gravado.
export const TEMPO_MAXIMO_MS = 15000;

class EtiquetasDaConversaAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  alterar(conversaId, { por = [], tirar = [] }) {
    return axios.patch(
      `${this.url}/${conversaId}/labels/alterar`,
      { por, tirar },
      { timeout: TEMPO_MAXIMO_MS }
    );
  }
}

export default new EtiquetasDaConversaAPI();
