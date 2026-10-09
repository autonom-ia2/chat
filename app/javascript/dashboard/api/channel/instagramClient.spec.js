/* global axios */
import instagramClient from './instagramClient';

beforeEach(() => {
  window.history.replaceState({}, '', '/app/accounts/17/settings/inboxes/new');
  vi.stubGlobal('axios', { get: vi.fn(), post: vi.fn() });
});
afterEach(() => vi.unstubAllGlobals());

describe('Instagram account-scoped API client', () => {
  it('preserves legacy authorization without tester payload', () => {
    instagramClient.generateAuthorization();
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/17/instagram/authorization',
      undefined
    );
  });

  it('passes the optional signed tester selection and cancellation options to authorization', () => {
    const options = { signal: new AbortController().signal };
    instagramClient.generateAuthorization(
      { tester_selection_token: 'signed-selection' },
      options
    );
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/17/instagram/authorization',
      { tester_selection_token: 'signed-selection' },
      options
    );
  });

  it('loads configuration and searches using the current account with signal', () => {
    const options = { signal: new AbortController().signal };
    instagramClient.getTesterConfiguration(options);
    instagramClient.searchTesters('demo_company', options);
    expect(axios.get).toHaveBeenNthCalledWith(
      1,
      '/api/v1/accounts/17/instagram/testers/configuration',
      options
    );
    expect(axios.get).toHaveBeenNthCalledWith(
      2,
      '/api/v1/accounts/17/instagram/testers/search',
      { ...options, params: { username: 'demo_company' } }
    );
  });

  it('passes invite_not_sent through from a failed invite operation', async () => {
    axios.post.mockResolvedValue({
      status: 202,
      data: {
        id: '00000000-0000-4000-8000-000000000001',
        request_id: '00000000-0000-4000-8000-000000000002',
        action: 'invite',
        state: 'failed',
        error_code: 'invite_not_sent',
        deadline: new Date(Date.now() + 60000).toISOString(),
      },
    });
    await expect(
      instagramClient.inviteTester('signed-selection')
    ).rejects.toMatchObject({
      response: { data: { error_code: 'invite_not_sent' } },
    });
  });

  describe('operation polling', () => {
    const operation = (state, deadline) => ({
      status: 202,
      data: {
        id: '00000000-0000-4000-8000-000000000001',
        request_id: '00000000-0000-4000-8000-000000000002',
        action: 'search',
        state,
        deadline,
      },
    });

    beforeEach(() => vi.useFakeTimers());
    afterEach(() => vi.useRealTimers());

    it('polls a queued operation again after 250 ms', async () => {
      const deadline = new Date(Date.now() + 60000).toISOString();
      axios.get
        .mockResolvedValueOnce(operation('queued', deadline))
        .mockResolvedValueOnce(operation('ready', deadline));

      const result = instagramClient.searchTesters('demo_company');
      await vi.advanceTimersByTimeAsync(249);
      expect(axios.get).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(1);
      expect(axios.get).toHaveBeenCalledTimes(2);
      expect(axios.get).toHaveBeenLastCalledWith(
        '/api/v1/accounts/17/instagram/testers/operations/00000000-0000-4000-8000-000000000001',
        expect.objectContaining({ timeout: 59750 })
      );
      await expect(result).resolves.toMatchObject({
        data: { state: 'ready' },
      });
    });

    it('never waits past the operation deadline', async () => {
      const deadline = new Date(Date.now() + 100).toISOString();
      axios.get.mockResolvedValueOnce(operation('queued', deadline));

      const result = instagramClient.searchTesters('demo_company');
      const rejection = expect(result).rejects.toMatchObject({
        response: { data: { error_code: 'meta_unavailable' } },
      });
      await vi.advanceTimersByTimeAsync(100);
      await rejection;
      expect(axios.get).toHaveBeenCalledTimes(1);
    });
  });

  it('sends selection tokens for status and invite, never raw target IDs', () => {
    const options = { signal: new AbortController().signal };
    instagramClient.getTesterStatus('signed-selection', options);
    instagramClient.inviteTester('signed-selection', options);
    expect(axios.post).toHaveBeenNthCalledWith(
      1,
      '/api/v1/accounts/17/instagram/testers/status',
      { selection_token: 'signed-selection' },
      options
    );
    expect(axios.post).toHaveBeenNthCalledWith(
      2,
      '/api/v1/accounts/17/instagram/testers/invite',
      { selection_token: 'signed-selection' },
      options
    );
  });
});
