import { pollAiRequest } from '../aiRequestPolling';

describe('pollAiRequest', () => {
  const originalAxios = window.axios;

  beforeEach(() => {
    vi.useFakeTimers();
    window.axios = { get: vi.fn() };
  });

  afterEach(() => {
    vi.useRealTimers();
    window.axios = originalAxios;
  });

  it('polls a pending request until it is done', async () => {
    window.axios.get
      .mockResolvedValueOnce({ data: { status: 'pending' } })
      .mockResolvedValueOnce({
        data: { status: 'done', result: { text: 'ok' } },
      });

    const request = pollAiRequest(
      Promise.resolve({
        status: 202,
        data: { poll_url: '/api/v1/accounts/85/ai_requests/request-1' },
      })
    );

    await vi.advanceTimersByTimeAsync(1000);
    expect(window.axios.get).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1000);

    await expect(request).resolves.toEqual({
      status: 200,
      data: { text: 'ok' },
    });
    expect(window.axios.get).toHaveBeenCalledTimes(2);
  });

  it('rejects with a generic error when the request fails', async () => {
    window.axios.get.mockResolvedValue({
      data: { status: 'failed', result: null },
    });

    const request = pollAiRequest(
      Promise.resolve({
        status: 202,
        data: { poll_url: '/api/v1/accounts/85/ai_requests/request-2' },
      })
    );
    const rejection = expect(request).rejects.toMatchObject({
      code: 'ai_request_failed',
      response: { data: { status: 'failed', result: null } },
    });

    await vi.advanceTimersByTimeAsync(1000);

    await rejection;
  });

  it('rejects when the request does not settle before the timeout', async () => {
    window.axios.get.mockResolvedValue({ data: { status: 'pending' } });
    const request = pollAiRequest(
      Promise.resolve({
        status: 202,
        data: { poll_url: '/api/v1/accounts/85/ai_requests/request-3' },
      }),
      { intervalMs: 1000, timeoutMs: 2000 }
    );
    const rejection = expect(request).rejects.toMatchObject({
      code: 'ai_request_timeout',
    });

    await vi.advanceTimersByTimeAsync(2000);

    await rejection;
    expect(window.axios.get).toHaveBeenCalledTimes(2);
  });

  it('returns legacy responses without polling', async () => {
    const response = { status: 200, data: { text: 'legacy' } };

    await expect(pollAiRequest(Promise.resolve(response))).resolves.toBe(
      response
    );
    expect(window.axios.get).not.toHaveBeenCalled();
  });

  it('keeps using the poll URL returned by the server after navigation', async () => {
    window.axios.get.mockResolvedValue({
      data: { status: 'done', result: { text: 'fixed account' } },
    });

    const request = pollAiRequest(
      Promise.resolve({
        status: 202,
        data: { poll_url: '/api/v1/accounts/85/ai_requests/request-4' },
      })
    );
    window.history.pushState({}, '', '/app/accounts/99/crm');

    await vi.advanceTimersByTimeAsync(1000);
    await expect(request).resolves.toEqual({
      status: 200,
      data: { text: 'fixed account' },
    });
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/ai_requests/request-4'
    );
  });
});
