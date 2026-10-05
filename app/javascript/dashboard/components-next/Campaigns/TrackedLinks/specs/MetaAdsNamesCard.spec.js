import { flushPromises, mount } from '@vue/test-utils';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import MetaAdsNamesCard from '../MetaAdsNamesCard.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { get: vi.fn(), update: vi.fn(), remove: vi.fn() },
}));

const NS = 'CRM_KANBAN.TRACKED_LINKS.META_ADS';
const TOKEN = 'EAAGm0PX4ZCpsBA-not-a-real-token';

const mountCard = async connection => {
  CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: connection });
  const wrapper = mount(MetaAdsNamesCard, {
    attachTo: document.body,
    global: {
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    },
  });
  await flushPromises();
  return wrapper;
};
const status = wrapper => wrapper.get('[data-testid="meta-ads-status"]').text();
const rejectWith = code => {
  const error = new Error('Request failed with status code 422');
  error.response = { status: 422, data: { error: code } };
  return error;
};
const submitToken = async (wrapper, token = TOKEN) => {
  await wrapper.get('[data-testid="meta-ads-connect"]').trigger('click');
  await wrapper.get('input[type="password"]').setValue(token);
  await wrapper.findAll('form')[0].trigger('submit');
  await flushPromises();
};

describe('MetaAdsNamesCard', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });
  beforeEach(() => {
    vi.clearAllMocks();
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('shows "not connected" with a Connect button', async () => {
    const wrapper = await mountCard({ configured: false });

    expect(status(wrapper)).toBe(`${NS}.STATUS.NOT_CONNECTED`);
    expect(wrapper.get('[data-testid="meta-ads-connect"]').text()).toBe(
      `${NS}.CONNECT`
    );
    expect(wrapper.find('[data-testid="meta-ads-remove"]').exists()).toBe(
      false
    );
  });

  it('shows "connected" with when it was last checked', async () => {
    const wrapper = await mountCard({
      configured: true,
      status: 'active',
      last_checked_at: new Date(Date.now() - 2 * 3600 * 1000).toISOString(),
    });

    expect(status(wrapper)).toBe(`${NS}.STATUS.CONNECTED`);
    expect(wrapper.text()).toContain(`${NS}.CHECKED`);
    expect(wrapper.text()).toContain(`${NS}.DESCRIPTION_CONNECTED`);
    expect(wrapper.get('[data-testid="meta-ads-connect"]').text()).toBe(
      `${NS}.REPLACE`
    );
  });

  it('asks for attention with the error Meta gave', async () => {
    const wrapper = await mountCard({
      configured: true,
      status: 'invalid',
      last_error: 'Session has expired',
    });

    expect(status(wrapper)).toBe(`${NS}.STATUS.ATTENTION`);
    expect(wrapper.get('[data-testid="meta-ads-attention"]').text()).toContain(
      `${NS}.LAST_ERROR`
    );
    expect(wrapper.get('[data-testid="meta-ads-connect"]').text()).toBe(
      `${NS}.RECONNECT`
    );
  });

  it('offers to try again when the connection cannot be read', async () => {
    CrmMetaAdsConnectionAPI.get.mockRejectedValue(new Error('offline'));
    const wrapper = mount(MetaAdsNamesCard, {
      global: {
        stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
      },
    });
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(`${NS}.LOAD_ERROR`);
    expect(wrapper.find('[data-testid="meta-ads-status"]').exists()).toBe(
      false
    );
  });

  it('tests and saves the pasted token, then shows it connected', async () => {
    const connected = {
      configured: true,
      status: 'active',
      last_checked_at: new Date().toISOString(),
    };
    CrmMetaAdsConnectionAPI.update.mockResolvedValue({ data: connected });
    const wrapper = await mountCard({ configured: false });

    await submitToken(wrapper, `  ${TOKEN}  `);

    expect(CrmMetaAdsConnectionAPI.update).toHaveBeenCalledWith(TOKEN);
    expect(status(wrapper)).toBe(`${NS}.STATUS.CONNECTED`);
    // The dialog closed and took the field (and the token) with it.
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
  });

  it('explains a token without ads_read', async () => {
    CrmMetaAdsConnectionAPI.update.mockRejectedValue(
      rejectWith('missing_ads_read')
    );
    const wrapper = await mountCard({ configured: false });

    await submitToken(wrapper);

    expect(wrapper.get('[data-testid="meta-ads-error"]').text()).toBe(
      `${NS}.DIALOG.ERROR_MISSING_ADS_READ`
    );
    expect(status(wrapper)).toBe(`${NS}.STATUS.NOT_CONNECTED`);
  });

  it('explains a token Meta refused, and any other failure', async () => {
    CrmMetaAdsConnectionAPI.update.mockRejectedValueOnce(
      rejectWith('invalid_token')
    );
    const wrapper = await mountCard({ configured: false });

    await submitToken(wrapper);
    expect(wrapper.get('[data-testid="meta-ads-error"]').text()).toBe(
      `${NS}.DIALOG.ERROR_INVALID_TOKEN`
    );

    CrmMetaAdsConnectionAPI.update.mockRejectedValueOnce(new Error('timeout'));
    await wrapper.findAll('form')[0].trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-testid="meta-ads-error"]').text()).toBe(
      `${NS}.DIALOG.ERROR_GENERIC`
    );
  });

  it.each([
    ['encryption_not_configured', 'ERROR_ENCRYPTION'],
    ['access_token_required', 'ERROR_TOKEN_REQUIRED'],
    ['forbidden', 'ERROR_FORBIDDEN'],
    ['meta_unavailable', 'ERROR_GENERIC'],
    ['no_ad_account', 'ERROR_NO_AD_ACCOUNT'],
    ['access_token_too_long', 'ERROR_INVALID_TOKEN'],
  ])('answers %s with its own text, not a blind retry', async (code, key) => {
    CrmMetaAdsConnectionAPI.update.mockRejectedValue(rejectWith(code));
    const wrapper = await mountCard({ configured: false });

    await submitToken(wrapper);

    expect(wrapper.get('[data-testid="meta-ads-error"]').text()).toBe(
      `${NS}.DIALOG.${key}`
    );
  });

  it('does not send an empty token', async () => {
    const wrapper = await mountCard({ configured: false });

    await submitToken(wrapper, '   ');

    expect(CrmMetaAdsConnectionAPI.update).not.toHaveBeenCalled();
  });

  it('removes the connection only after confirming', async () => {
    CrmMetaAdsConnectionAPI.remove.mockResolvedValue({});
    const wrapper = await mountCard({ configured: true, status: 'active' });

    await wrapper.get('[data-testid="meta-ads-remove"]').trigger('click');
    expect(CrmMetaAdsConnectionAPI.remove).not.toHaveBeenCalled();

    await wrapper.findAll('form')[1].trigger('submit');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.remove).toHaveBeenCalledTimes(1);
    expect(status(wrapper)).toBe(`${NS}.STATUS.NOT_CONNECTED`);
  });
});
