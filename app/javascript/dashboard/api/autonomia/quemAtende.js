/* global axios */
import ApiClient from '../ApiClient';

// #1648 — quem atende a caixa (aba "Agente de IA"). A leitura devolve
// { agentes: [{ tipo, id, name, papel, avatar_url }], primeiro: { tipo, id, name } | null,
//   opcoes: [{ tipo, id, name, recusa }] }.
// `papel`: 'porta' atende primeiro, 'area' recebe quando alguém passa.
// `tipo`: 'plataforma' (agente da plataforma) ou 'webhook' (agente de outro
// sistema); a tela não separa os dois, só usa para saber onde abrir e o que
// mandar na troca. `recusa`: código do motivo pelo qual o servidor recusaria
// esta opção agora (ou null).
// A troca é completa: o servidor tira quem atende primeiro e põe o novo, numa
// transação só, e responde a leitura nova. 422 { error, code } na recusa.
class AutonomiaQuemAtendeAPI extends ApiClient {
  constructor() {
    super('autonomia/inboxes', { accountScoped: true });
  }

  daCaixa(inboxId) {
    return axios.get(`${this.url}/${inboxId}/quem_atende`);
  }

  // `agente`: { tipo, id } ou null (ninguém atende primeiro, só pessoas).
  trocar(inboxId, agente) {
    let corpo = { nenhum: true };
    if (agente?.tipo === 'webhook') corpo = { agent_bot_id: agente.id };
    else if (agente) corpo = { agent_id: agente.id };
    return axios.put(`${this.url}/${inboxId}/quem_atende`, corpo);
  }
}

export default new AutonomiaQuemAtendeAPI();
