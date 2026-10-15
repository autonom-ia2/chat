/* global axios */
import ApiClient from './ApiClient';

// #1460 — lembrete que repete: ver a série, mudar "esta e as próximas",
// pausar, retomar e encerrar. Cada chamada devolve o payload já desembrulhado.
class CrmFollowUpSeriesAPI extends ApiClient {
  constructor() {
    super('crm/follow_up_series', { accountScoped: true });
  }

  async buscar(id) {
    const { data } = await axios.get(`${this.url}/${id}`);
    return data.payload;
  }

  async mudar(id, serie) {
    const { data } = await axios.patch(`${this.url}/${id}`, {
      follow_up_series: serie,
    });
    return data.payload;
  }

  async pausar(id) {
    const { data } = await axios.post(`${this.url}/${id}/pause`);
    return data.payload;
  }

  async retomar(id) {
    const { data } = await axios.post(`${this.url}/${id}/resume`);
    return data.payload;
  }

  async encerrar(id) {
    const { data } = await axios.post(`${this.url}/${id}/end`);
    return data.payload;
  }
}

export default new CrmFollowUpSeriesAPI();
