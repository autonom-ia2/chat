/* global axios */
import ApiClient from './ApiClient';

// Módulo Cotação (Insurance). Uma conexão por provider e conta; a senha só viaja no POST de
// criação e nunca volta em nenhuma resposta (o backend devolve apenas `username_hint`).
class AutonomiaInsuranceAPI extends ApiClient {
  constructor() {
    super('autonomia/insurance', { accountScoped: true });
  }

  getConnection(provider = 'agger') {
    return axios.get(`${this.url}/connection`, { params: { provider } });
  }

  connect({ username, password }, provider = 'agger') {
    return axios.post(`${this.url}/connection`, {
      provider,
      connection: { username, password },
    });
  }

  reconnect(provider = 'agger') {
    return axios.post(`${this.url}/connection/reconnect`, { provider });
  }

  rescan(provider = 'agger') {
    return axios.post(`${this.url}/connection/scan`, { provider });
  }

  removeConnection(provider = 'agger') {
    return axios.delete(`${this.url}/connection`, { params: { provider } });
  }
}

export default new AutonomiaInsuranceAPI();
