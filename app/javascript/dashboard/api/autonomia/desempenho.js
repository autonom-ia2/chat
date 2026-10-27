/* global axios */
import ApiClient from '../ApiClient';

// #2251 — o painel de desempenho do agente (Api::V1::Accounts::Autonomia::Agents::DesempenhoController).
//   painel   → { data: Painel do contrato v2 do período } (ou { versao: 2, vazio: true, meta: { situacao } } sem leitura)
//   exportar → { data: Blob } do PDF ou da planilha do mesmo período, montado na hora pelo servidor. Vai pelo axios
//              (e não por um link direto) porque a API pede os cabeçalhos de autenticação.
// `origem`: 'webhook' para o robô de outro sistema (os ids podem coincidir com os dos agentes nossos, #1648).
// 404 com a flag agentes_painel_desempenho desligada; 401 sem desempenho_view.
const parametros = ({ origem, periodo }) => ({
  periodo,
  ...(origem === 'webhook' ? { origem: 'webhook' } : {}),
});

class AutonomiaDesempenhoAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  painel({ agentId, origem, periodo }) {
    return axios.get(`${this.url}/${agentId}/desempenho`, {
      params: parametros({ origem, periodo }),
    });
  }

  exportar({ agentId, origem, periodo, formato }) {
    return axios.get(`${this.url}/${agentId}/desempenho/exportar`, {
      params: { formato, ...parametros({ origem, periodo }) },
      responseType: 'blob',
    });
  }
}

export default new AutonomiaDesempenhoAPI();
