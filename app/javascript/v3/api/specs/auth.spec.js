import { beforeEach, describe, expect, it, vi } from 'vitest';
import wootAPI from '../apiClient';
import { login } from '../auth';

vi.mock('../apiClient', () => ({
  default: { post: vi.fn() },
}));

vi.mock('dashboard/store/utils/api', () => ({
  setAuthCredentials: vi.fn(),
  clearLocalStorageOnLogout: vi.fn(),
  parseAPIErrorResponse: error => error.message,
  throwErrorMessage: vi.fn(),
}));

describe('v3 login API errors', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('preserves the response status used to classify an invalid SSO token', async () => {
    wootAPI.post.mockRejectedValue(
      Object.assign(new Error('Invalid login credentials'), {
        response: { status: 401, data: {} },
      })
    );

    await expect(
      login({ email: 'agent@example.com', sso_auth_token: 'invalid-token' })
    ).rejects.toMatchObject({
      message: 'Invalid login credentials',
      status: 401,
    });
  });

  it('keeps network failures distinct from authentication responses', async () => {
    wootAPI.post.mockRejectedValue(new Error('Network Error'));

    await expect(
      login({ email: 'agent@example.com', sso_auth_token: 'sso-token' })
    ).rejects.toMatchObject({
      message: 'Network Error',
      status: undefined,
    });
  });
});
