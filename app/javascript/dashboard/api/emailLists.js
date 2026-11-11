/* global axios */
import ApiClient from './ApiClient';

// G52 (#2760) — as listas de e-mail da conta: o público "lista X" da campanha
// de e-mail e do passo "Pôr na lista de e-mail" da Automação livre.
class EmailListsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/lists', { accountScoped: true });
  }

  index() {
    return axios.get(this.url);
  }

  create(name) {
    return axios.post(this.url, { email_list: { name } });
  }
}

export default new EmailListsAPI();
