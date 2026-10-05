/* global axios */
import ApiClient from './ApiClient';

// Meta ads read credential of the account (docs/crm/origens-nomes-meta.md §2).
// The token only goes out on update; no response ever carries it back.
class CrmMetaAdsConnectionAPI extends ApiClient {
  constructor() {
    super('crm/meta_ads_connection', { accountScoped: true });
  }

  // { configured, status, last_checked_at, last_error }
  get() {
    return axios.get(this.url);
  }

  // Meta tests the token before it is saved: 422 with error
  // 'missing_ads_read' or 'invalid_token' when it cannot be used.
  update(accessToken) {
    return axios.put(this.url, { access_token: accessToken });
  }

  remove() {
    return axios.delete(this.url);
  }
}

export default new CrmMetaAdsConnectionAPI();
