/* global axios */
import ApiClient from './ApiClient';

class OnboardingProgressAPI extends ApiClient {
  constructor() {
    super('onboarding/progress', { accountScoped: true });
  }

  skip(passoId) {
    return axios.post(`${this.url}/${passoId}/skip`);
  }

  resume(passoId) {
    return axios.post(`${this.url}/${passoId}/resume`);
  }
}

export default new OnboardingProgressAPI();
