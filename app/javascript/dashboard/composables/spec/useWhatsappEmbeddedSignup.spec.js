import {
  useWhatsappEmbeddedSignup,
  FINISH_AFTER_CODE_MS,
  SIGNUP_SAFETY_CAP_MS,
  SIGNUP_TIMEOUT_CODE,
} from '../useWhatsappEmbeddedSignup';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';

// The event classifier is exercised through the composable rather than stubbed, so
// these specs cover the real v3/v4 event-name handling.
vi.mock(
  'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils',
  async importOriginal => ({
    ...(await importOriginal()),
    setupFacebookSdk: vi.fn(),
    initWhatsAppEmbeddedSignup: vi.fn(),
    createMessageHandler: vi.fn(),
  })
);

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const flushPromises = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

const createDeferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

const VALID_BUSINESS = {
  business_id: 'biz-1',
  waba_id: 'waba-1',
  phone_number_id: 'phone-1',
};

describe('useWhatsappEmbeddedSignup', () => {
  // The mocked createMessageHandler captures the callback the composable
  // registers, so tests can simulate Meta's WA_EMBEDDED_SIGNUP postMessages
  // directly without the window-event + origin plumbing (that is covered by
  // the utils' own tests).
  let signupCallback;
  let registeredListener;

  const emit = data => signupCallback(data);

  // Fake timers must never leak into the next test, even when an assertion fails.
  afterEach(() => {
    vi.useRealTimers();
  });

  beforeEach(() => {
    vi.clearAllMocks();

    window.chatwootConfig = {
      whatsappAppId: 'app-id',
      whatsappConfigurationId: 'config-id',
      whatsappApiVersion: 'v22.0',
    };

    setupFacebookSdk.mockResolvedValue();
    createMessageHandler.mockImplementation(callback => {
      signupCallback = callback;
      registeredListener = () => {};
      return registeredListener;
    });
  });

  it('resolves credentials when the auth code arrives before the business data', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await flushPromises(); // SDK setup + FB.login resolve the code first
    emit({ event: 'FINISH', data: VALID_BUSINESS });

    await expect(result).resolves.toEqual({
      code: 'auth-code',
      business_id: 'biz-1',
      waba_id: 'waba-1',
      phone_number_id: 'phone-1',
      is_coexistence: false,
    });
    expect(setupFacebookSdk).toHaveBeenCalledWith('app-id', 'v22.0');
    expect(initWhatsAppEmbeddedSignup).toHaveBeenCalledWith('config-id');
  });

  it('resolves credentials when the business data arrives before the auth code', async () => {
    const code = createDeferred();
    initWhatsAppEmbeddedSignup.mockReturnValue(code.promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    // Business data lands first, while FB.login is still pending.
    emit({
      event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
      data: VALID_BUSINESS,
    });
    code.resolve('late-code');

    await expect(result).resolves.toEqual({
      code: 'late-code',
      business_id: 'biz-1',
      waba_id: 'waba-1',
      phone_number_id: 'phone-1',
      is_coexistence: true,
    });
  });

  it('resolves a coexistence completion that only carries waba_id', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await flushPromises();
    emit({
      event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
      data: { waba_id: 'waba-1' },
    });

    await expect(result).resolves.toEqual({
      code: 'auth-code',
      business_id: '',
      waba_id: 'waba-1',
      phone_number_id: '',
      is_coexistence: true,
    });
  });

  it('defaults phone_number_id to an empty string when absent', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await flushPromises();
    emit({
      event: 'FINISH',
      data: { business_id: 'biz-1', waba_id: 'waba-1' },
    });

    await expect(result).resolves.toMatchObject({ phone_number_id: '' });
  });

  // Regression: this event was unhandled, so the promise stayed pending
  // forever and the UI spun with no error — the Royalty Seguros symptom.
  it('resolves on FINISH_ONLY_WABA, which carries no phone number', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await flushPromises();
    emit({ event: 'FINISH_ONLY_WABA', data: { waba_id: 'waba-1' } });

    // No coexistence signal on this event: null lets the backend fall back to
    // Meta's health data (an explicit false would skip that check).
    await expect(result).resolves.toEqual({
      code: 'auth-code',
      business_id: '',
      waba_id: 'waba-1',
      phone_number_id: '',
      is_coexistence: null,
    });
  });

  it('rejects instead of hanging when Meta never sends the business data', async () => {
    vi.useFakeTimers();
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup, isAuthenticating } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();
    const assertion = expect(result).rejects.toMatchObject({
      message: expect.stringMatching(/timed out waiting for business data/),
      code: SIGNUP_TIMEOUT_CODE,
    });

    await vi.advanceTimersByTimeAsync(FINISH_AFTER_CODE_MS);
    await assertion;
    // The composable must unlock, otherwise a retry is impossible.
    expect(isAuthenticating.value).toBe(false);
  });

  // #1228: a coexistence signup done calmly took more than 5 minutes inside Meta's
  // window; the old cap reported an error although Meta had finished.
  it('keeps waiting while the person is still inside the Facebook window', async () => {
    vi.useFakeTimers();
    const code = createDeferred();
    initWhatsAppEmbeddedSignup.mockReturnValue(code.promise);

    const { runEmbeddedSignup, isAuthenticating } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();
    const pending = Symbol('pending');

    await vi.advanceTimersByTimeAsync(20 * 60 * 1000);
    expect(isAuthenticating.value).toBe(true);
    await expect(
      Promise.race([result, Promise.resolve(pending)])
    ).resolves.toBe(pending);

    emit({ event: 'FINISH', data: VALID_BUSINESS });
    code.resolve('slow-code');

    await expect(result).resolves.toMatchObject({
      code: 'slow-code',
      waba_id: 'waba-1',
    });
  });

  it('resolves when Meta confirms within the wait after the window closes', async () => {
    vi.useFakeTimers();
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await vi.advanceTimersByTimeAsync(FINISH_AFTER_CODE_MS - 1);
    emit({ event: 'FINISH', data: VALID_BUSINESS });

    await expect(result).resolves.toMatchObject({ code: 'auth-code' });
    expect(vi.getTimerCount()).toBe(0);
  });

  it('does not start the short wait when Meta confirmed before the window closed', async () => {
    vi.useFakeTimers();
    const code = createDeferred();
    initWhatsAppEmbeddedSignup.mockReturnValue(code.promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'FINISH', data: VALID_BUSINESS });
    await vi.advanceTimersByTimeAsync(FINISH_AFTER_CODE_MS * 5);
    code.resolve('late-code');

    await expect(result).resolves.toMatchObject({ code: 'late-code' });
    expect(vi.getTimerCount()).toBe(0);
  });

  // #1228: Meta said it finished, then the window closed without a code. Saying
  // "cancelled" would tell the user nothing happened.
  it('does not report a cancel after Meta confirmed the signup', async () => {
    const code = createDeferred();
    initWhatsAppEmbeddedSignup.mockReturnValue(code.promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'FINISH', data: VALID_BUSINESS });
    code.reject(new Error('Login cancelled'));

    await expect(result).rejects.toMatchObject({ code: SIGNUP_TIMEOUT_CODE });
  });

  it('gives up on a Facebook window that never answers at all', async () => {
    vi.useFakeTimers();
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();
    const assertion = expect(result).rejects.toMatchObject({
      code: SIGNUP_TIMEOUT_CODE,
    });

    await vi.advanceTimersByTimeAsync(SIGNUP_SAFETY_CAP_MS);
    await assertion;
  });

  // Root cause of the Royalty Seguros incident (27/07): Meta refused the
  // signup after the customer switched accounts while confirming. It emits
  // ERROR uppercase with the reason in data.data.error_message; the handler
  // compared against lowercase 'error', so nothing settled the promise.
  it('rejects with Meta reason on an uppercase ERROR event', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({
      event: 'ERROR',
      data: { error_message: 'Unable to connect this account' },
    });

    await expect(result).rejects.toThrow('Unable to connect this account');
  });

  it('still handles the legacy lowercase error payload shape', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'error', error_message: 'legacy shape' });

    await expect(result).rejects.toThrow('legacy shape');
  });

  it('resolves null when FB.login is cancelled', async () => {
    initWhatsAppEmbeddedSignup.mockRejectedValue(new Error('Login cancelled'));

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();

    await expect(runEmbeddedSignup()).resolves.toBeNull();
  });

  it('resolves null on a CANCEL event', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'CANCEL' });

    await expect(result).resolves.toBeNull();
  });

  it.each(['error', 'ERROR'])(
    'rejects with the Meta error message on a %s event',
    async event => {
      initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

      const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
      const result = runEmbeddedSignup();

      emit({ event, error_message: 'WABA not eligible' });

      await expect(result).rejects.toThrow('WABA not eligible');
    }
  );

  it('rejects a CANCEL that carries an error message rather than treating it as a dismissal', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'CANCEL', error_message: 'Phone number already in use' });

    await expect(result).rejects.toThrow('Phone number already in use');
  });

  it('rejects with Meta reason on a CANCEL that nests error_message in data', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({
      event: 'CANCEL',
      data: { error_message: 'Phone number already in use', error_id: '524' },
    });

    await expect(result).rejects.toThrow('Phone number already in use');
  });

  // Kept from #225: the backend (Whatsapp::PhoneInfoService) resolves the WABA's
  // only number or fails with a clear error, so these completions still go there
  // instead of being refused up front.
  it.each([
    'FINISH_ONLY_WABA',
    'FINISH_OBO_MIGRATION',
    'FINISH_GRANT_ONLY_API_ACCESS',
  ])('hands the %s completion to the backend', async event => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await flushPromises();
    emit({ event, data: { waba_id: 'waba-1' } });

    await expect(result).resolves.toEqual({
      code: 'auth-code',
      business_id: '',
      waba_id: 'waba-1',
      phone_number_id: '',
      is_coexistence: null,
    });
  });

  it('stays pending on a non-terminal event', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();
    const pending = Symbol('pending');

    await flushPromises();
    emit({ event: 'SOMETHING_ELSE', current_step: 'PHONE_NUMBER_SELECTION' });

    await expect(
      Promise.race([result, Promise.resolve(pending)])
    ).resolves.toBe(pending);

    // Let the run finish so it doesn't leak into the next test.
    emit({ event: 'FINISH', data: VALID_BUSINESS });
    await result;
  });

  it('rejects when the business data is invalid', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'FINISH', data: { business_id: 'biz-1' } }); // no waba_id

    await expect(result).rejects.toThrow(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.INVALID_BUSINESS_DATA'
    );
  });

  it('rejects when the SDK or login fails for a non-cancel reason', async () => {
    initWhatsAppEmbeddedSignup.mockRejectedValue(new Error('popup blocked'));

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();

    await expect(runEmbeddedSignup()).rejects.toThrow('popup blocked');
  });

  it('ignores a second call while a run is in flight', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const first = runEmbeddedSignup();
    const second = runEmbeddedSignup();

    await expect(second).resolves.toBeNull();

    // Let the first run finish so it doesn't leak into the next test.
    await flushPromises();
    emit({ event: 'FINISH', data: VALID_BUSINESS });
    await first;

    expect(setupFacebookSdk).toHaveBeenCalledTimes(1);
  });

  it('toggles isAuthenticating and removes the listener once settled', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    const removeSpy = vi.spyOn(window, 'removeEventListener');

    const { isAuthenticating, runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    expect(isAuthenticating.value).toBe(false);

    const result = runEmbeddedSignup();
    expect(isAuthenticating.value).toBe(true);

    await flushPromises();
    emit({ event: 'FINISH', data: VALID_BUSINESS });
    await result;

    expect(isAuthenticating.value).toBe(false);
    expect(removeSpy).toHaveBeenCalledWith('message', registeredListener);
    removeSpy.mockRestore();
  });
});
