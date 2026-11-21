import { flushPromises, shallowMount } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import oauthAPI from 'dashboard/api/oauth';
import Authorize from '../Authorize.vue';

const OAUTH_QUERY = {
  client_id: 'abc',
  redirect_uri: 'https://chatgpt.com/callback',
  response_type: 'code',
  state: 'xyz',
  code_challenge: 'challenge',
  code_challenge_method: 'S256',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, params) => `${key} ${params?.appName || ''}` }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: '7' },
    query: { ...OAUTH_QUERY, account_id: '99', utm_source: 'ad' },
  }),
}));

const ADMIN_ACCOUNT = {
  id: 7,
  name: 'Acme',
  role: 'administrator',
  status: 'active',
};
const mockCurrentUser = vi.hoisted(() => ({ value: { accounts: [] } }));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mockCurrentUser,
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));

vi.mock('dashboard/api/oauth', () => ({
  default: {
    getAuthorization: vi.fn(),
    approveAuthorization: vi.fn(),
    denyAuthorization: vi.fn(),
  },
}));

describe('Authorize', () => {
  const mountComponent = async () => {
    const wrapper = shallowMount(Authorize);
    await flushPromises();
    return wrapper;
  };

  beforeEach(() => {
    mockCurrentUser.value = { accounts: [ADMIN_ACCOUNT] };
    delete window.location;
    window.location = { assign: vi.fn() };
    oauthAPI.getAuthorization.mockResolvedValue({
      data: {
        client_name: 'ChatGPT',
        scope: 'conversations:read messages:write',
        redirect_uri: 'https://chatgpt.com/callback',
      },
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('loads the request with only the OAuth parameters from the URL', async () => {
    await mountComponent();

    expect(oauthAPI.getAuthorization).toHaveBeenCalledWith(OAUTH_QUERY);
  });

  it('shows the app name and the requested scopes', async () => {
    const wrapper = await mountComponent();

    expect(wrapper.text()).toContain('OAUTH.AUTHORIZE.TITLE ChatGPT');
    expect(wrapper.text()).toContain('OAUTH.SCOPES.CONVERSATIONS_READ');
    expect(wrapper.text()).toContain('OAUTH.SCOPES.MESSAGES_WRITE');
  });

  it('approves for the account in the route and sends the browser to the client', async () => {
    oauthAPI.approveAuthorization.mockResolvedValue({
      data: { redirect_uri: 'https://chatgpt.com/callback?code=123' },
    });
    const wrapper = await mountComponent();

    await wrapper.findAllComponents(Button)[1].trigger('click');
    await flushPromises();

    expect(oauthAPI.approveAuthorization).toHaveBeenCalledWith({
      ...OAUTH_QUERY,
      account_id: 7,
    });
    expect(window.location.assign).toHaveBeenCalledWith(
      'https://chatgpt.com/callback?code=123'
    );
  });

  it('denies and sends the browser to the client', async () => {
    oauthAPI.denyAuthorization.mockResolvedValue({
      data: {
        redirect_uri: 'https://chatgpt.com/callback?error=access_denied',
      },
    });
    const wrapper = await mountComponent();

    await wrapper.findAllComponents(Button)[0].trigger('click');
    await flushPromises();

    expect(oauthAPI.denyAuthorization).toHaveBeenCalledWith(OAUTH_QUERY);
    expect(window.location.assign).toHaveBeenCalledWith(
      'https://chatgpt.com/callback?error=access_denied'
    );
  });

  it('shows the address that receives the access', async () => {
    const wrapper = await mountComponent();

    expect(wrapper.text()).toContain('OAUTH.AUTHORIZE.REDIRECT_LABEL');
    expect(wrapper.text()).toContain('chatgpt.com');
  });

  it('names the only account instead of asking to choose one', async () => {
    const wrapper = await mountComponent();

    expect(wrapper.text()).toContain('OAUTH.AUTHORIZE.ACCOUNT_SINGLE');
  });

  it('lets someone who administers no account only go back to the app', async () => {
    mockCurrentUser.value = {
      accounts: [
        { ...ADMIN_ACCOUNT, role: 'agent' },
        { ...ADMIN_ACCOUNT, id: 8, status: 'suspended' },
      ],
    };
    oauthAPI.denyAuthorization.mockResolvedValue({
      data: {
        redirect_uri: 'https://chatgpt.com/callback?error=access_denied',
      },
    });
    const wrapper = await mountComponent();

    expect(wrapper.text()).toContain('OAUTH.AUTHORIZE.NO_ADMIN_TITLE');
    const buttons = wrapper.findAllComponents(Button);
    expect(buttons).toHaveLength(1);

    await buttons[0].trigger('click');
    await flushPromises();

    expect(oauthAPI.approveAuthorization).not.toHaveBeenCalled();
    expect(oauthAPI.denyAuthorization).toHaveBeenCalledWith(OAUTH_QUERY);
  });

  it('shows a plain error, without the server text, and a way out when the request is not valid', async () => {
    oauthAPI.getAuthorization.mockRejectedValue({
      response: { data: { error_description: 'Client authentication failed' } },
    });
    const wrapper = await mountComponent();

    expect(wrapper.text()).toContain('OAUTH.AUTHORIZE.ERROR_TITLE');
    expect(wrapper.text()).not.toContain('Client authentication failed');

    await wrapper.findAllComponents(Button)[0].trigger('click');

    expect(window.location.assign).toHaveBeenCalledWith('/app');
  });

  it('offers to try again when the server cannot be reached', async () => {
    oauthAPI.getAuthorization.mockRejectedValueOnce(new Error('Network Error'));
    const wrapper = await mountComponent();

    expect(wrapper.text()).toContain('OAUTH.AUTHORIZE.NETWORK_ERROR_TITLE');

    await wrapper.findAllComponents(Button)[0].trigger('click');
    await flushPromises();

    expect(oauthAPI.getAuthorization).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('OAUTH.AUTHORIZE.TITLE ChatGPT');
  });
});
