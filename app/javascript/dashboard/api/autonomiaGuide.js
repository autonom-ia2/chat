/* global axios */
import ApiClient from './ApiClient';

// Guia da Plataforma — onboarding/suporte read-only, global (gated server-side by the account's
// Autonomia eligibility = ENV master + the Kanban AI key).
class AutonomiaGuideAPI extends ApiClient {
  constructor() {
    super('autonomia/guide', { accountScoped: true });
  }

  // history: [{ role: 'user' | 'assistant', content }]
  // routeContext: the current route name (so the guide knows where the user is).
  chat({ message, history, routeContext } = {}) {
    return axios.post(`${this.url}/chat`, {
      message,
      history,
      route_context: routeContext,
    });
  }

  // Só é chamado depois da confirmação explícita na tela. O backend recusa o que
  // estiver fora do catálogo de ações e o que a pessoa não puder fazer.
  executarAcao({ acao, dados } = {}) {
    return axios.post(`${this.url}/acoes/executar`, { acao, dados });
  }
}

export default new AutonomiaGuideAPI();
