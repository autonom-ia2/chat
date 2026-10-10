/* global axios */
/* eslint-disable no-await-in-loop -- Poll one operation serially until completion or cancellation. */
import ApiClient from '../ApiClient';

const OPERATION_POLL_INTERVAL = 250;
const OPERATION_STATES = ['queued', 'running', 'ready', 'failed', 'expired'];
const OPERATION_ERRORS = new Set([
  'invalid_username',
  'invalid_selection',
  'meta_unavailable',
  'meta_session_expired',
  'unknown_status',
  'invite_rejected',
  'invite_unknown',
  'invite_not_sent',
  'rate_limited',
  'forbidden',
  'not_enabled',
  'busy',
  'proxy_unavailable',
  'session_update_rejected',
  'operator_required',
]);
const OPERATION_ID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const operationError = code => {
  const error = new Error(code);
  error.response = { data: { error_code: code } };
  return error;
};

const waitForOperationPoll = (signal, remaining) =>
  new Promise((resolve, reject) => {
    signal?.throwIfAborted();
    let timer;
    const abort = () => {
      clearTimeout(timer);
      reject(signal.reason);
    };
    timer = setTimeout(
      () => {
        signal?.removeEventListener('abort', abort);
        resolve();
      },
      Math.min(OPERATION_POLL_INTERVAL, remaining)
    );
    signal?.addEventListener('abort', abort, { once: true });
  });

class InstagramChannel extends ApiClient {
  constructor() {
    super('instagram', { accountScoped: true });
  }

  generateAuthorization(payload, options) {
    const request = options
      ? axios.post(`${this.url}/authorization`, payload, options)
      : axios.post(`${this.url}/authorization`, payload);
    return this.resolveOperation(request, 'authorization', options);
  }

  getTesterConfiguration(options) {
    return axios.get(`${this.url}/testers/configuration`, options);
  }

  searchTesters(username, options) {
    return this.resolveOperation(
      axios.get(`${this.url}/testers/search`, {
        ...options,
        params: { username },
      }),
      'search',
      options
    );
  }

  getTesterStatus(selectionToken, options) {
    return this.resolveOperation(
      axios.post(
        `${this.url}/testers/status`,
        { selection_token: selectionToken },
        options
      ),
      'status',
      options
    );
  }

  inviteTester(selectionToken, options) {
    return this.resolveOperation(
      axios.post(
        `${this.url}/testers/invite`,
        { selection_token: selectionToken },
        options
      ),
      'invite',
      options
    );
  }

  async resolveOperation(request, action, options) {
    let response = await request;
    if (response?.status !== 202) return response;
    if (!response.data || typeof response.data !== 'object')
      throw operationError('meta_unavailable');
    const { id, request_id: requestId, deadline } = response.data;
    const expiresAt = Date.parse(deadline);
    if (
      !OPERATION_ID.test(id) ||
      !OPERATION_ID.test(requestId) ||
      typeof deadline !== 'string' ||
      !Number.isFinite(expiresAt)
    )
      throw operationError('meta_unavailable');

    const operationUrl = `${this.url}/testers/operations/${id}`;
    while (Date.now() < expiresAt) {
      options?.signal?.throwIfAborted();
      const data = response.data;
      if (
        !data ||
        typeof data !== 'object' ||
        data.id !== id ||
        data.request_id !== requestId ||
        data.action !== action ||
        data.deadline !== deadline ||
        !OPERATION_STATES.includes(data.state)
      )
        throw operationError('meta_unavailable');
      if (data.state === 'ready') return response;
      if (['failed', 'expired'].includes(data.state))
        throw operationError(
          OPERATION_ERRORS.has(data.error_code)
            ? data.error_code
            : 'meta_unavailable'
        );
      await waitForOperationPoll(options?.signal, expiresAt - Date.now());
      const remaining = expiresAt - Date.now();
      if (remaining <= 0) throw operationError('meta_unavailable');
      try {
        response = await axios.get(operationUrl, {
          signal: options?.signal,
          timeout: remaining,
        });
      } catch (error) {
        if (Date.now() >= expiresAt) throw operationError('meta_unavailable');
        throw error;
      }
    }
    throw operationError('meta_unavailable');
  }
}

export default new InstagramChannel();
