/* global axios */
import ApiClient from './ApiClient';

// Browser errors go to our own server log (#1841). Only the flow, the status and the stack: never
// the request, the e-mail body or headers.
class ClientErrorsAPI extends ApiClient {
  constructor() {
    super('client_errors', { accountScoped: true });
  }

  report({ flow, error }) {
    return axios.post(this.url, {
      flow,
      status: error?.response?.status ?? null,
      message: String(error?.message || error).slice(0, 500),
      stack: String(error?.stack || '').slice(0, 4000),
    });
  }
}

export default new ClientErrorsAPI();
