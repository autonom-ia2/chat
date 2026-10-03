import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { login } from '../../../api/auth';
import Login from '../Index.vue';

vi.mock('../../../api/auth', () => ({
  login: vi.fn(),
}));

const buildContext = () => {
  const context = {
    email: 'agent@example.com',
    ssoAuthToken: 'one-time-sso-token',
    ssoAccountId: '',
    ssoConversationId: '',
    redirectTo: '',
    credentials: { email: '', password: '' },
    loginApi: { message: '', showLoading: false, hasErrored: false },
    ssoLoginFailure: null,
    redirectingToAutonomia: false,
    shouldAutoRedirectToAutonomia: false,
    autonomiaSsoUrl: '/auth/autonomia',
    $t: key => key,
    $router: { push: vi.fn() },
  };

  Object.entries(Login.methods).forEach(([name, method]) => {
    context[name] = method.bind(context);
  });

  Object.defineProperty(context, 'autonomiaRetryUrl', {
    get: () => Login.computed.autonomiaRetryUrl.call(context),
  });

  return context;
};

describe('Autonomia SSO login failure recovery', () => {
  let originalLocation;
  let assign;

  beforeEach(() => {
    originalLocation = window.location;
    assign = vi.fn();
    delete window.location;
    window.location = { origin: originalLocation.origin, assign };
  });

  afterEach(() => {
    delete window.location;
    window.location = originalLocation;
    vi.clearAllMocks();
  });

  it.each([400, 401, 403, 410, 422])(
    'stops the loader and returns terminal SSO status %s to a fresh Auth login',
    async status => {
      const error = Object.assign(new Error('Invalid login credentials'), {
        status,
      });
      login.mockRejectedValue(error);
      const context = buildContext();

      context.submitLogin();
      await vi.waitFor(() => expect(context.loginApi.showLoading).toBe(false));

      expect(context.ssoLoginFailure).toBe('authentication');
      expect(Login.computed.showSilentSsoLoader.call(context)).toBe(false);
      expect(assign).toHaveBeenCalledOnce();
      expect(assign).toHaveBeenCalledWith('/auth/autonomia?prompt=login');
    }
  );

  it('stops the loader without redirecting after a transient network failure', async () => {
    login.mockRejectedValue(new Error('Network Error'));
    const context = buildContext();

    context.submitLogin();
    await vi.waitFor(() => expect(context.loginApi.showLoading).toBe(false));

    expect(context.ssoLoginFailure).toBe('transient');
    expect(Login.computed.showSilentSsoLoader.call(context)).toBe(false);
    expect(assign).not.toHaveBeenCalled();
  });

  it('keeps a temporary server failure on the retry screen', async () => {
    login.mockRejectedValue(
      Object.assign(new Error('Service unavailable'), { status: 503 })
    );
    const context = buildContext();

    context.submitLogin();
    await vi.waitFor(() => expect(context.loginApi.showLoading).toBe(false));

    expect(context.ssoLoginFailure).toBe('transient');
    expect(assign).not.toHaveBeenCalled();
  });

  it('allows a new attempt after a transient failure without restarting Auth', async () => {
    login
      .mockRejectedValueOnce(new Error('Network Error'))
      .mockResolvedValueOnce();
    const context = buildContext();

    context.submitLogin();
    await vi.waitFor(() => expect(context.ssoLoginFailure).toBe('transient'));

    context.submitLogin();
    await vi.waitFor(() => expect(login).toHaveBeenCalledTimes(2));

    expect(context.ssoLoginFailure).toBeNull();
    expect(context.loginApi.showLoading).toBe(false);
    expect(assign).not.toHaveBeenCalled();
  });

  it('keeps a successful SSO login out of the failure recovery path', async () => {
    login.mockResolvedValue();
    const context = buildContext();

    context.submitLogin();
    await vi.waitFor(() => expect(context.loginApi.showLoading).toBe(false));

    expect(context.ssoLoginFailure).toBeNull();
    expect(assign).not.toHaveBeenCalled();
  });

  it('preserves only an internal app target in the Auth retry URL', () => {
    const context = buildContext();
    context.redirectTo = '/app/accounts/7/dashboard?conversation=2';

    expect(context.autonomiaRetryUrl).toBe(
      '/auth/autonomia?prompt=login&return_to=%2Fapp%2Faccounts%2F7%2Fdashboard%3Fconversation%3D2'
    );
    expect(context.autonomiaRetryUrl).not.toContain(context.email);
    expect(context.autonomiaRetryUrl).not.toContain(context.ssoAuthToken);
  });

  it('drops an external return target from the Auth retry URL', () => {
    const context = buildContext();
    context.redirectTo = 'https://evil.example/steal';

    expect(context.autonomiaRetryUrl).toBe('/auth/autonomia?prompt=login');
  });

  it('does not follow an externally configured retry URL', () => {
    const context = buildContext();
    context.autonomiaSsoUrl = 'https://evil.example/login';

    expect(context.autonomiaRetryUrl).toBe('/auth/autonomia?prompt=login');
  });

  it('does not automatically redirect an Auth error page back into SSO', () => {
    const context = buildContext();
    context.ssoAuthToken = '';
    context.email = '';
    context.authError = 'autonomia-sso-error';
    context.showAutonomiaSso = true;
    window.chatwootConfig = { autonomiaSsoAutoRedirect: 'true' };

    expect(Login.computed.shouldAutoRedirectToAutonomia.call(context)).toBe(
      false
    );
    expect(assign).not.toHaveBeenCalled();
  });
});
