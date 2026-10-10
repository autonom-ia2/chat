import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enBrand from 'dashboard/i18n/locale/en/brandKits.json';
import BrandKitsAPI from 'dashboard/api/brandKits';
import { resetBrandKits } from '../useBrandKits';
import RequestedSiteNotice from '../RequestedSiteNotice.vue';

vi.mock('dashboard/api/brandKits', () => ({
  default: { list: vi.fn(), siteReading: vi.fn(), save: vi.fn() },
}));

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const proposal = {
  name: 'Aurora',
  source_url: 'https://aurora.example/',
  appearance: { palettes: {} },
  logo_candidates: [{ url: 'https://aurora.example/logo.png' }],
};

const mountNotice = siteRequest => {
  const module = getters => ({ namespaced: true, getters });
  const store = createStore({
    getters: {
      getCurrentUser: () => ({ accounts: [{ id: 1, permissions: [] }] }),
      getCurrentCustomRoleId: () => null,
      getCurrentAccountId: () => 1,
    },
    modules: {
      inboxes: module({ getInboxes: () => [] }),
      emailSenderIdentities: module({ getIdentities: () => [] }),
      globalConfig: module({ get: () => ({ brandKitsEnabled: true }) }),
      accounts: module({ isFeatureEnabledonAccount: () => () => true }),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: enBrand },
  });
  return mount(RequestedSiteNotice, {
    props: { siteRequest },
    global: { plugins: [store, i18n] },
  });
};

// #1111: the request named a site for the identity of the e-mail.
describe('RequestedSiteNotice', () => {
  beforeEach(() => {
    resetBrandKits();
    vi.clearAllMocks();
    BrandKitsAPI.list.mockResolvedValue({
      data: {
        payload: [{ id: 1, name: 'Aurora', is_default: true }],
        meta: { archived_count: 0, google_fonts: [] },
      },
    });
  });

  it('says the site asked for was used', () => {
    const wrapper = mountNotice({
      host: 'aurora.example',
      status: 'used',
      import_id: 9,
    });

    expect(wrapper.text()).toContain(
      'I used the identity of aurora.example, as you asked.'
    );
    expect(wrapper.find('[data-test="site-request-save"]').exists()).toBe(true);
  });

  it('says the site could not be read and the default went instead, without saving', () => {
    const wrapper = mountNotice({
      host: 'aurora.example',
      status: 'unreadable',
    });

    expect(wrapper.text()).toContain(
      'I could not read aurora.example. I used the default identity.'
    );
    expect(wrapper.find('[data-test="site-request-save"]').exists()).toBe(
      false
    );
  });

  it('saves the site as an identity with the reading kept on the server', async () => {
    BrandKitsAPI.siteReading.mockResolvedValue({
      data: { status: 'succeeded', proposal },
    });
    BrandKitsAPI.save.mockResolvedValue({
      data: { id: 7, name: 'Aurora 2' },
    });
    const wrapper = mountNotice({
      host: 'aurora.example',
      status: 'used',
      import_id: 9,
    });

    await wrapper.find('[data-test="site-request-save"]').trigger('click');
    await flushPromises();

    expect(BrandKitsAPI.siteReading).toHaveBeenCalledWith(9);
    expect(BrandKitsAPI.save).toHaveBeenCalledWith(null, {
      name: 'Aurora 2',
      source_url: 'https://aurora.example/',
      appearance: proposal.appearance,
      logo_source_url: 'https://aurora.example/logo.png',
    });
    expect(wrapper.text()).toContain('Identity Aurora 2 saved.');
    expect(wrapper.find('[data-test="site-request-save"]').exists()).toBe(
      false
    );
  });

  it('tells when saving fails', async () => {
    BrandKitsAPI.siteReading.mockRejectedValue(new Error('offline'));
    const wrapper = mountNotice({
      host: 'aurora.example',
      status: 'used',
      import_id: 9,
    });

    await wrapper.find('[data-test="site-request-save"]').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Could not save the identity.');
  });
});
