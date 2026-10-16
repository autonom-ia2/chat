/* global axios */
import ApiClient from './ApiClient';

// #1149 — CRM → Caixas no CRM: listar as caixas, abrir uma e salvar a caixa
// inteira de uma vez. Cada chamada devolve o payload já desembrulhado.
class CrmCaixasAPI extends ApiClient {
  constructor() {
    super('crm/caixas', { accountScoped: true });
  }

  async listar() {
    const { data } = await axios.get(this.url);
    return data.payload;
  }

  async buscar(inboxId) {
    const { data } = await axios.get(`${this.url}/${inboxId}`);
    return data.payload;
  }

  // #1140 — só lê: quem receberia cada assunto com o que a tela marcou, pela
  // regra do motor de entrega. { triagem: [ids], funis: { id: [ids] } }
  async quemRecebe(inboxId, caixa) {
    const { data } = await axios.post(`${this.url}/${inboxId}/quem_recebe`, {
      caixa,
    });
    return data.payload.quem_recebe;
  }

  async salvar(inboxId, caixa) {
    const { data } = await axios.put(`${this.url}/${inboxId}`, { caixa });
    return data.payload;
  }
}

export default new CrmCaixasAPI();
