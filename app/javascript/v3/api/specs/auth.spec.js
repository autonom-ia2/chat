import { beforeEach, describe, expect, it, vi } from 'vitest';
import wootAPI from '../apiClient';
import {
  login,
  register,
  resendConfirmation,
  verifyPasswordToken,
} from '../auth';
import { setAuthCredentials } from 'dashboard/store/utils/api';

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

describe('auth API', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('keeps the regular signup payload unchanged', async () => {
    wootAPI.post.mockResolvedValue({ data: { email: 'john@acme.com' } });

    await register({
      email: 'john@acme.com',
      password: 'Password1!',
      hCaptchaClientResponse: 'captcha-token',
    });

    expect(wootAPI.post).toHaveBeenCalledWith('api/v1/accounts.json', {
      account_name: 'Acme',
      user_full_name: 'John',
      email: 'john@acme.com',
      password: 'Password1!',
      h_captcha_client_response: 'captcha-token',
    });
  });

  it('includes the pending install token for Shopify signup', async () => {
    wootAPI.post.mockResolvedValue({ data: { email: 'john@acme.com' } });

    await register({
      email: 'john@acme.com',
      password: 'Password1!',
      hCaptchaClientResponse: 'captcha-token',
      shopifyPendingInstallToken: 'pending-install-token',
    });

    expect(wootAPI.post).toHaveBeenCalledWith(
      'api/v1/accounts.json',
      expect.objectContaining({
        shopify_pending_install_token: 'pending-install-token',
      })
    );
  });
  it('returns the authenticated user after email confirmation', async () => {
    const user = { id: 1, accounts: [{ id: 2 }] };
    const response = { data: { data: user } };
    wootAPI.post.mockResolvedValue(response);

    await expect(
      verifyPasswordToken({ confirmationToken: 'confirmation-token' })
    ).resolves.toEqual(user);
    expect(setAuthCredentials).toHaveBeenCalledWith(response);
  });

  it('includes the pending install redirect when resending confirmation', async () => {
    const redirectUrl = `settings/integrations/shopify?shopify_pending_install=${'a'.repeat(32)}`;

    await resendConfirmation({
      email: 'john@acme.com',
      hCaptchaClientResponse: 'captcha-token',
      redirectUrl,
    });

    expect(wootAPI.post).toHaveBeenCalledWith('resend_confirmation', {
      email: 'john@acme.com',
      h_captcha_client_response: 'captcha-token',
      redirect_url: redirectUrl,
    });
  });
});
