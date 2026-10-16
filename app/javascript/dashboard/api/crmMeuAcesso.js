/* global axios */
import ApiClient from './ApiClient';

// #1149 (R16): as caixas em que a pessoa logada tem acesso restrito por funil.
class CrmMeuAcessoAPI extends ApiClient {
  constructor() {
    super('crm/meu_acesso', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }
}

export default new CrmMeuAcessoAPI();
