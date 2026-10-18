import ClientErrorsAPI from '../clientErrors';

// #1841: only the flow, the status and the stack leave the browser, never the request inside the error.
describe('Client errors API', () => {
  const originalAxios = window.axios;
  const axiosMock = { post: vi.fn(() => Promise.resolve()) };

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/campaigns');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('sends the flow, status, message and stack and nothing from the request', () => {
    const error = Object.assign(
      new Error('Request failed with status code 500'),
      {
        response: { status: 500, data: { secret: 'x' } },
        config: {
          data: '{"email_campaign":{"body_html":"<p>CPF 123</p>"}}',
          headers: { 'access-token': 'token-value' },
        },
      }
    );

    ClientErrorsAPI.report({ flow: 'email_builder_save', error });

    const [url, payload] = axiosMock.post.mock.calls[0];
    expect(url).toBe('/api/v1/accounts/85/client_errors');
    expect(Object.keys(payload).sort()).toEqual([
      'flow',
      'message',
      'stack',
      'status',
    ]);
    expect(payload).toMatchObject({
      flow: 'email_builder_save',
      status: 500,
      message: 'Request failed with status code 500',
    });
    expect(JSON.stringify(payload)).not.toContain('CPF');
    expect(JSON.stringify(payload)).not.toContain('token-value');
  });

  it('sends a null status when the error never reached the server', () => {
    ClientErrorsAPI.report({
      flow: 'email_builder_save',
      error: new Error('export failed'),
    });

    expect(axiosMock.post.mock.calls[0][1]).toMatchObject({
      status: null,
      message: 'export failed',
    });
  });
});
