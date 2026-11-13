/* global axios */
import ApiClient from '../ApiClient';

// #2931 — os pedidos do passo "Pedir aprovação", do lado de quem aprova: os
// abertos, um pedido (aberto ou já respondido) e a resposta.
class AprovacoesAPI extends ApiClient {
  constructor() {
    super('autonomia/aprovacoes', { accountScoped: true });
  }

  responder(id, { aprovado, motivo }) {
    return axios.post(`${this.url}/${id}/responder`, { aprovado, motivo });
  }
}

export default new AprovacoesAPI();
