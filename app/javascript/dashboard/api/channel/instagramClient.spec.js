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
