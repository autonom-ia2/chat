/* global axios */
import ApiClient from './ApiClient';

// Guia da Plataforma — onboarding/suporte global (gated server-side by the account's Autonomia
// eligibility = ENV master + the Kanban AI key). `chat` apenas explica; `executarAcao` muda dados,
// e só é chamado depois da confirmação explícita na tela.
class AutonomiaGuideAPI extends ApiClient {
  constructor() {
    super('autonomia/guide', { accountScoped: true });
  }

  // history: [{ role: 'user' | 'assistant', content }]
  // routeContext: the current route name (so the guide knows where the user is).
  //
  // #572 — não devolve a resposta: abre o pedido e devolve { id, status }. O
  // Guia trabalha num job, e a resposta se busca em `resposta(id)`. Responder
  // aqui dentro esbarrava no teto de 15s do servidor e morria com erro 500.
  chat({ message, history, routeContext } = {}) {
    return axios.post(`${this.url}/chat`, {
      message,
      history,
      route_context: routeContext,
    });
  }

  // { status: 'pending' } enquanto o Guia pensa; depois 'done' com a resposta
  // (text, navigation, acao, retido…) ou 'failed'.
  resposta(id) {
    return axios.get(`${this.url}/chat/${id}`);
  }

  // Só é chamado depois da confirmação explícita na tela. O backend recusa o que
  // estiver fora do catálogo de ações e o que a pessoa não puder fazer.
  executarAcao({ acao, dados } = {}) {
    return axios.post(`${this.url}/acoes/executar`, { acao, dados });
  }
}

export default new AutonomiaGuideAPI();
