import ApiClient from '../ApiClient';

// #858 — Decisores da conta. `get()` (herdado) devolve
// { decisores: [{ id, nome, pergunta, respostas: [{ chave, descricao }], ... }] }.
class AutonomiaDecisoresAPI extends ApiClient {
  constructor() {
    super('autonomia/decisores', { accountScoped: true });
  }
}

export default new AutonomiaDecisoresAPI();
