import { shallowMount, flushPromises } from '@vue/test-utils';
import Facebook from '../Facebook.vue';

const { loginAndFetchPages, preloadSdk } = vi.hoisted(() => ({
  loginAndFetchPages: vi.fn(),
  preloadSdk: vi.fn(),
}));

vi.mock('../../../../../index', () => ({ default: { replace: vi.fn() } }));
vi.mock('@sentry/vue', () => ({ captureException: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isMetaInboxCreationDisabled: false }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));
vi.mock('dashboard/composables/useFacebookPageConnect', () => ({
  FACEBOOK_NOT_CONFIGURED: 'FacebookNotConfigured',
  useFacebookPageConnect: () => ({ preloadSdk, loginAndFetchPages }),
}));

const failure = name => Object.assign(new Error(name), { name });

const mountPage = () =>
  shallowMount(Facebook, {
    global: {
      mocks: { $t: key => key, $store: { dispatch: vi.fn() } },
      stubs: { NextButton: { template: '<button><slot /></button>' } },
    },
  });

const startLogin = async wrapper => {
  await wrapper.find('button').trigger('click');
  await flushPromises();
};

// #2319: a failed login used to leave "Authenticating you with Facebook..." on screen forever.
describe('Facebook page connect', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    preloadSdk.mockResolvedValue();
  });

  it.each([
    ['the person cancels the login', () => Promise.resolve(null), 'CANCELLED'],
    [
      'the SDK is blocked',
      () => Promise.reject(failure('ScriptLoaderError')),
      'BLOCKED',
    ],
    [
      'fetching the pages fails',
      () => Promise.reject(new Error('500')),
      'FAILED',
    ],
  ])(
    'leaves the loader and offers a retry when %s',
    async (_case, result, reason) => {
      loginAndFetchPages.mockImplementationOnce(result);
      const wrapper = mountPage();
      await startLogin(wrapper);

      const error = wrapper.find('[data-fb-login-error]');
      expect(error.text()).toContain(
        `INBOX_MGMT.DETAILS.FB_LOGIN_ERROR.${reason}.TITLE`
      );
      expect(error.text()).toContain(
        `INBOX_MGMT.DETAILS.FB_LOGIN_ERROR.${reason}.HELP`
      );
      expect(wrapper.findComponent({ name: 'LoadingState' }).exists()).toBe(
        false
      );

      loginAndFetchPages.mockResolvedValueOnce({
        userAccessToken: 'token',
        pages: [{ id: 'p1', name: 'Page One' }],
      });
      await wrapper.find('[data-fb-login-retry]').trigger('click');
      await flushPromises();

      expect(loginAndFetchPages).toHaveBeenCalledTimes(2);
      expect(wrapper.find('[data-fb-login-error]').exists()).toBe(false);
      expect(wrapper.find('form').exists()).toBe(true);
    }
  );

  it('maps FacebookNotConfigured to the not-set-up message, without a retry', async () => {
    preloadSdk.mockRejectedValue(failure('FacebookNotConfigured'));
    loginAndFetchPages.mockRejectedValueOnce(failure('FacebookNotConfigured'));
    const wrapper = mountPage();
    await startLogin(wrapper);

    expect(wrapper.find('[data-fb-login-error]').text()).toContain(
      'INBOX_MGMT.DETAILS.FB_LOGIN_ERROR.NOT_CONFIGURED.TITLE'
    );
    expect(wrapper.find('[data-fb-login-retry]').exists()).toBe(false);
  });
});
