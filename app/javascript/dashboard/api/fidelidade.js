/* global axios */
import ApiClient from './ApiClient';

// #3100 — o cartão fidelidade da conta (fidelidade/…): ler (o cartão ou
// null), criar ou mudar as regras (PUT), pausar ou ligar de novo (PATCH) e os
// números do painel. Ver pede fidelidade_view; mudar, fidelidade_manage (o
// servidor responde 401 a quem não pode). O que é da pessoa (o cartão dela,
// o histórico, dar o prêmio) mora em dashboard/api/relacionamentos.js.
class FidelidadeAPI extends ApiClient {
  constructor() {
    super('fidelidade', { accountScoped: true });
  }

  programa() {
    return axios.get(`${this.url}/programa`);
  }

  // `programa`: { tipo, a_cada (reais inteiros), ganha, meta, premio, validade_meses }.
  salvarPrograma(programa) {
    return axios.put(`${this.url}/programa`, { programa });
  }

  ligarPrograma(ligado) {
    return axios.patch(`${this.url}/programa`, { ligado });
  }

  resumo() {
    return axios.get(`${this.url}/resumo`);
  }
}

export default new FidelidadeAPI();
