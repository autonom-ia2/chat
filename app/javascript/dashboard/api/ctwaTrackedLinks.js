/* global axios */
import ApiClient from './ApiClient';

class CtwaTrackedLinksAPI extends ApiClient {
  constructor() {
    super('ctwa_tracked_links', { accountScoped: true });
  }

  get(options = {}) {
    return axios.get(this.url, options);
  }
}

export default new CtwaTrackedLinksAPI();
