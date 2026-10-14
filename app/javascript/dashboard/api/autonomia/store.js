/* global axios */
import ApiClient from '../ApiClient';

class AutonomiaStoreAPI extends ApiClient {
  constructor() {
    super('autonomia/financial/store', { accountScoped: true });
  }

  catalog(page, signal) {
    return axios.get(`${this.url}/catalog`, {
      params: { page, page_size: 20 },
      signal,
    });
  }

  features(signal) {
    return axios.get(`${this.url}/features`, { signal });
  }

  subscriptions(page, signal, serviceCatalogItemId) {
    return axios.get(`${this.url}/subscriptions`, {
      params: {
        page,
        page_size: 20,
        ...(serviceCatalogItemId ? { serviceCatalogItemId } : {}),
      },
      signal,
    });
  }

  eligibleAccounts(signal) {
    return axios.get(`${this.url}/eligible-accounts`, { signal });
  }

  cancellationCapability(id, signal) {
    return axios.get(
      `${this.url}/subscriptions/${encodeURIComponent(id)}/cancellation`,
      { signal }
    );
  }

  subscriptionCommand(id, action, payload) {
    const suffix = action === 'resume' ? '/resume' : '';
    return axios.post(
      `${this.url}/subscriptions/${encodeURIComponent(id)}/cancellation${suffix}`,
      payload
    );
  }

  commandStatus(id, signal) {
    return axios.get(
      `${this.url}/subscription-commands/${encodeURIComponent(id)}`,
      { signal }
    );
  }

  retryCommand(id) {
    return axios.post(
      `${this.url}/subscription-commands/${encodeURIComponent(id)}/retry`
    );
  }

  checkout(payload) {
    return axios.post(`${this.url}/checkout`, payload);
  }

  resolveCheckout(clientIntent) {
    return axios.post(`${this.url}/checkout/resolve`, { clientIntent });
  }

  checkoutStatus(id, signal) {
    return axios.get(`${this.url}/checkout/${encodeURIComponent(id)}`, {
      signal,
    });
  }

  reconcileCheckout(id) {
    return axios.post(
      `${this.url}/checkout/${encodeURIComponent(id)}/reconcile`
    );
  }

  activate(payload) {
    return axios.post(`${this.url}/activations`, payload);
  }

  activation(id, signal) {
    return axios.get(`${this.url}/activations/${encodeURIComponent(id)}`, {
      signal,
    });
  }

  deactivate(id) {
    return axios.post(
      `${this.url}/activations/${encodeURIComponent(id)}/deactivate`
    );
  }

  resumeActivation(id) {
    return axios.post(
      `${this.url}/activations/${encodeURIComponent(id)}/resume`
    );
  }

  resourceUrl(target) {
    const resource = target.agentId
      ? `agents/${encodeURIComponent(target.agentId)}`
      : `features/${encodeURIComponent(target.featureKey)}`;
    return `${this.url}/${resource}/services`;
  }

  services(target, signal) {
    return axios.get(this.resourceUrl(target), { signal });
  }

  createService(target, payload) {
    return axios.post(this.resourceUrl(target), payload);
  }

  publication(target, serviceId, signal) {
    return axios.get(
      `${this.resourceUrl(target)}/${encodeURIComponent(serviceId)}/publication`,
      { signal }
    );
  }

  publish(target, serviceId, payload) {
    return axios.put(
      `${this.resourceUrl(target)}/${encodeURIComponent(serviceId)}/publication`,
      payload
    );
  }
}

export default new AutonomiaStoreAPI();
