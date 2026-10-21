/* global axios */
import ApiClient from '../ApiClient';
import { pollAiRequest } from '../../helper/aiRequestPolling';

// #1429 F3 — a base de seguros do agente (Api::V1::Accounts::Autonomia::Agents::BaseDeSegurosController).
//   ler/atualizar/desfazer → { data: { situacao, atual, nova, pode_atualizar, desfazer } }
//     situacao: 'em_dia' | 'sem_base' | 'antiga' | 'conta_mudou' | null (null = a linha não aparece)
//     atual:    { segmento, data } | null          (null = trabalha sem base)
//     nova:     { segmento, data, versao } | null
//     desfazer: { anterior: { segmento, data } | null } | null  (existe logo depois de atualizar)
//   comparar → { data: { perguntas: [{ pergunta, hoje, hoje_equipe, nova, nova_equipe }] } } (job, com poll)
class BaseDoAgenteAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  ler(agentId) {
    return axios.get(`${this.url}/${agentId}/base`);
  }

  comparar(agentId) {
    return pollAiRequest(axios.post(`${this.url}/${agentId}/base/comparar`));
  }

  // `versao`: a da base nova que a pessoa viu; o servidor recusa (409) se ela mudou.
  atualizar(agentId, versao) {
    return axios.post(`${this.url}/${agentId}/base/atualizar`, { versao });
  }

  desfazer(agentId) {
    return axios.post(`${this.url}/${agentId}/base/desfazer`);
  }
}

export default new BaseDoAgenteAPI();
