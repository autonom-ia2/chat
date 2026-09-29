import transport from '../relationships';
import createAxios from 'dashboard/helper/APIHelper';
import axios from 'axios';

const originalClient = window.axios;
const originalConfig = window.chatwootConfig;
afterEach(() => {
  window.axios = originalClient;
  window.chatwootConfig = originalConfig;
  vi.restoreAllMocks();
});

it('uses the configured dashboard instance, not the unauthenticated package singleton', async () => {
  window.chatwootConfig = { apiHost: 'https://isolated-api.example.test' };
  const configured = createAxios(axios);
  configured.defaults.headers.common['access-token'] = 'synthetic-session';
  const requests = [];
  configured.defaults.adapter = async config => {
    requests.push(config);
    return {
      data: { ok: true },
      status: 200,
      statusText: 'OK',
      headers: {},
      config,
    };
  };
  window.axios = configured;
  const rawGet = vi.spyOn(axios, 'get');
  const response = await transport.get(
    '/api/v1/accounts/8/relationships/configuration'
  );
  expect(response.data).toEqual({ ok: true });
  expect(requests[0].baseURL).toBe('https://isolated-api.example.test/');
  expect(requests[0].headers.get('access-token')).toBe('synthetic-session');
  expect(rawGet).not.toHaveBeenCalled();
});

it('resolves a replaced authenticated client after the session changes', async () => {
  const first = { get: vi.fn().mockResolvedValue({ data: 1 }) };
  const second = {
    get: vi.fn().mockResolvedValue({ data: 2 }),
    patch: vi.fn(),
    post: vi.fn(),
  };
  window.axios = first;
  await transport.get('/first');
  window.axios = second;
  await transport.get('/second', { responseType: 'blob' });
  transport.patch('/value', { field: { value: false } });
  transport.post('/remove', { custom_attributes: ['test'] });
  expect(first.get).toHaveBeenCalledTimes(1);
  expect(second.get).toHaveBeenCalledWith('/second', { responseType: 'blob' });
  expect(second.patch).toHaveBeenCalledWith('/value', {
    field: { value: false },
  });
  expect(second.post).toHaveBeenCalledWith('/remove', {
    custom_attributes: ['test'],
  });
});
