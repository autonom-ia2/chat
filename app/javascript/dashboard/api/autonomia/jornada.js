/* global axios */
import ApiClient from '../ApiClient';

// #1181 — leituras da nova jornada de Agentes, atrás da flag autonomia_agents_journey (404 sem ela).
// L1 `numeros_da_semana`: conversas respondidas e passadas para a equipe nos últimos 7 dias, por agente.
// L2 `canais_ocupados`: caixas da conta e quem responde em cada uma (agente nativo ou outro sistema).
// Só as telas novas chamam: o seletor da rota e o menu não importam este arquivo.
class AutonomiaJornadaAPI extends ApiClient {
  constructor() {
    super('autonomia', { accountScoped: true });
  }

  semana({ agentId } = {}) {
    const params = agentId ? { agent_id: agentId } : {};
    return axios.get(`${this.url}/numeros_da_semana`, { params });
  }

  canaisOcupados() {
    return axios.get(`${this.url}/canais_ocupados`);
  }
}

export default new AutonomiaJornadaAPI();
