/* global axios */
import ApiClient from '../ApiClient';

class InstagramChannel extends ApiClient {
  constructor() {
    super('instagram', { accountScoped: true });
  }

  generateAuthorization(payload, options) {
    if (options)
      return axios.post(`${this.url}/authorization`, payload, options);
    return axios.post(`${this.url}/authorization`, payload);
  }

  getTesterConfiguration(options) {
    return axios.get(`${this.url}/testers/configuration`, options);
  }

  searchTesters(username, options) {
    return axios.get(`${this.url}/testers/search`, {
      ...options,
      params: { username },
    });
  }

  getTesterStatus(selectionToken, options) {
    return axios.post(
      `${this.url}/testers/status`,
      { selection_token: selectionToken },
      options
    );
  }

  inviteTester(selectionToken, options) {
    return axios.post(
      `${this.url}/testers/invite`,
      { selection_token: selectionToken },
      options
    );
  }
}

export default new InstagramChannel();
