/* global axios */
import ApiClient from './ApiClient';

// Seus posts (#2302, F1 #2304): the account's Instagram and Facebook Page
// posts, read through their inboxes (SeusPosts::Leitura). 403 when the seat
// has no posts_view; 404 when the profile is not in the account.
class SeusPostsAPI extends ApiClient {
  constructor() {
    super('seus_posts', { accountScoped: true });
  }

  // { days, from, to, perfil, perfis: [{ id, network, name }] }
  get({ perfil, days }) {
    return axios.get(this.url, { params: { perfil, days } });
  }
}

export default new SeusPostsAPI();
