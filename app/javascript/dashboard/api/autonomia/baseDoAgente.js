/* global axios */
import ApiClient from '../ApiClient';
import { pollAiRequest } from '../../helper/aiRequestPolling';

// #1429 F3 — a base de seguros do agente (Api::V1::Accounts::Autonomia::Agents::BaseDeSegurosController).
//   ler/atualizar/desfazer → { data: { situacao, atual, nova, pode_atualizar, desfazer } }
//     situacao: 'em_dia' | 'sem_base' | 'antiga' | 'conta_mudou' | null (null = a linha não aparece)
//     atual:    { segmento, data } | null          (null = trabalha sem base)
//     nova:     { segmento, data, versao } | null
//     desfazer: { anterior: { segmento, data } | null } | null  (existe logo depois de atualizar)
//   comparar → { data: { versao, perguntas: [{ pergunta, hoje, hoje_equipe, nova, nova_equipe }] } } (job, com poll; 200
//              na hora quando há uma comparação pronta desta versão dos últimos 2 minutos)
//   erros com { error, code }: 422 sem_base_nova | sem_instrucao | comparar_antes, 409 base_mudou | desfazer_fechado,
//              429 comparar_espere | comparar_amanha
class BaseDoAgenteAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  ler(agentId) {
    return axios.get(`${this.url}/${agentId}/base`);
  }

  // `signal`: fechar a gaveta para o poll (AbortController).
  comparar(agentId, signal) {
    return pollAiRequest(
      axios.post(`${this.url}/${agentId}/base/comparar`, {}, { signal }),
      { signal }
    );
  }

  // `versao`: a da base nova que a pessoa comparou; o servidor recusa (409) se ela mudou.
  atualizar(agentId, versao) {
    return axios.post(`${this.url}/${agentId}/base/atualizar`, { versao });
  }

  desfazer(agentId) {
    return axios.post(`${this.url}/${agentId}/base/desfazer`);
  }
}

export default new BaseDoAgenteAPI();
