import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import enBrand from 'dashboard/i18n/locale/en/brandKits.json';
import ptBrand from 'dashboard/i18n/locale/pt_BR/brandKits.json';
import BrandKitsAPI from 'dashboard/api/brandKits';
import { resetBrandKits } from 'dashboard/components-next/BrandKits/useBrandKits';

vi.mock('dashboard/api/brandKits', () => ({
  default: {
    list: vi.fn(),
    setDefault: vi.fn(() => Promise.resolve({})),
    archive: vi.fn(() => Promise.resolve({})),
    restore: vi.fn(() => Promise.resolve({})),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const push = vi.fn();
const currentRoute = {
  name: 'campaigns_journey_brand_kits',
  query: {},
  params: {},
};
vi.mock('vue-router', () => ({
  useRouter: () => ({ push, resolve: () => ({ href: '/x' }) }),
  useRoute: () => currentRoute,
}));

const { default: BrandKitsPage } = await import('../BrandKitsPage.vue');

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const palettes = {
  light: {
    primary: '#c8102e',
    accent: '#0ab9d1',
    ink: '#0b243f',
    background: '#ffffff',
    band: '#0b243f',
  },
  dark: { primary: '#ff1f2d', background: '#0b243f', band: '#0b243f' },
};
const kit = (id, name, extra = {}) => ({
  id,
  name,
  is_default: false,
  archived_at: null,
  source_url: 'https://hub2you.ai/',
  appearance: {
    palettes,
    typography: { heading_font: 'MuseoModerno', body_font: 'Roboto' },
  },
  logo: null,
  ...extra,
});

const listResponse = (payload, archivedCount = 0) =>
  Promise.resolve({
    data: {
      payload,
      meta: { archived_count: archivedCount, google_fonts: [] },
    },
  });

const mountPage = ({ customRole = null, locale = 'en' } = {}) => {
  const module = getters => ({ namespaced: true, getters });
  const store = createStore({
    getters: {
      getCurrentUser: () => ({
        accounts: [{ id: 1, permissions: customRole || [] }],
      }),
      getCurrentCustomRoleId: () => (customRole ? 7 : null),
      getCurrentAccountId: () => 1,
    },
    modules: {
      inboxes: module({
        getInboxes: () => [
          { channel_type: 'Channel::Email', email: 'a@b.c', id: 1 },
        ],
      }),
      emailSenderIdentities: module({
        getIdentities: () => [{ id: 1, status: 'verified' }],
      }),
      globalConfig: module({
        get: () => ({
          emailCampaignEnabled: true,
          crmKanbanEnabled: true,
          brandKitsEnabled: true,
        }),
      }),
      accounts: module({ isFeatureEnabledonAccount: () => () => true }),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale,
    messages: {
      en: { ...enJourney, ...enBrand },
      pt_BR: { ...enJourney, ...ptBrand },
    },
  });
  return mount(BrandKitsPage, {
    attachTo: document.body,
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': { template: '<a><slot /></a>' },
        BrandKitEditor: true,
      },
    },
  });
};

describe('Identidade visual (#1076)', () => {
  beforeEach(() => {
    resetBrandKits();
    push.mockClear();
    Object.assign(currentRoute, {
      name: 'campaigns_journey_brand_kits',
      query: {},
      params: {},
    });
    Object.values(BrandKitsAPI).forEach(fn => fn.mockClear());
  });

  it('empty: one sentence and one button that starts from the website', async () => {
    BrandKitsAPI.list.mockReturnValue(listResponse([]));
    const wrapper = mountPage({ locale: 'pt_BR' });
    await flushPromises();

    const empty = wrapper.find('[data-test="empty-state"]');
    expect(empty.text()).toContain(
      'Guarde a logo, as cores e a fonte da sua marca.'
    );
    expect(empty.findAll('button')).toHaveLength(1);
    await wrapper.find('[data-test="use-my-site"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_brand_kit_new',
      query: {},
    });
    wrapper.unmount();
  });

  it('lists identities with the default marked, and the default cannot be archived', async () => {
    BrandKitsAPI.list.mockReturnValue(
      listResponse([
        kit(1, 'Hub2You', { is_default: true }),
        kit(2, 'Autonomia'),
      ])
    );
    const wrapper = mountPage();
    await flushPromises();

    expect(
      wrapper.find('[data-kit="1"] [data-test="default-badge"]').exists()
    ).toBe(true);
    await wrapper
      .find('[data-kit="1"] [data-test="kit-more"]')
      .trigger('click');
    expect(
      wrapper
        .find('[data-kit="1"] [data-test="kit-archive"]')
        .attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('[data-kit="1"] [data-test="kit-make-default"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it('archives after a confirmation inside the card and tells where the archived ones are', async () => {
    BrandKitsAPI.list
      .mockReturnValueOnce(
        listResponse([
          kit(1, 'Hub2You', { is_default: true }),
          kit(2, 'Autonomia'),
        ])
      )
      .mockReturnValue(
        listResponse([kit(1, 'Hub2You', { is_default: true })], 1)
      );
    const wrapper = mountPage();
    await flushPromises();

    await wrapper
      .find('[data-kit="2"] [data-test="kit-more"]')
      .trigger('click');
    await wrapper
      .find('[data-kit="2"] [data-test="kit-archive"]')
      .trigger('click');
    expect(BrandKitsAPI.archive).not.toHaveBeenCalled();
    await wrapper
      .find('[data-kit="2"] [data-test="kit-archive-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(BrandKitsAPI.archive).toHaveBeenCalledWith(2);
    expect(wrapper.find('[data-kit="2"]').exists()).toBe(false);
    expect(wrapper.find('[data-test="toggle-archived"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('makes another identity the default from the more menu', async () => {
    BrandKitsAPI.list.mockReturnValue(
      listResponse([
        kit(1, 'Hub2You', { is_default: true }),
        kit(2, 'Autonomia'),
      ])
    );
    const wrapper = mountPage();
    await flushPromises();

    await wrapper
      .find('[data-kit="2"] [data-test="kit-more"]')
      .trigger('click');
    await wrapper
      .find('[data-kit="2"] [data-test="kit-make-default"]')
      .trigger('click');
    await flushPromises();

    expect(BrandKitsAPI.setDefault).toHaveBeenCalledWith(2);
    wrapper.unmount();
  });

  it('restores an archived identity from the archived list', async () => {
    currentRoute.query = { archived: '1' };
    BrandKitsAPI.list.mockImplementation(({ archived } = {}) =>
      archived
        ? listResponse([kit(3, 'Antiga', { archived_at: '2026-10-01' })])
        : listResponse([kit(1, 'Hub2You', { is_default: true })], 1)
    );
    const wrapper = mountPage();
    await flushPromises();

    await wrapper
      .find('[data-kit="3"] [data-test="kit-restore"]')
      .trigger('click');
    await flushPromises();

    expect(BrandKitsAPI.restore).toHaveBeenCalledWith(3);
    wrapper.unmount();
  });

  it('read-only seat (campaign_view) sees the identities without buttons that change them', async () => {
    BrandKitsAPI.list.mockReturnValue(
      listResponse([kit(1, 'Hub2You', { is_default: true })])
    );
    const wrapper = mountPage({ customRole: ['campaign_view'] });
    await flushPromises();

    expect(wrapper.find('[data-kit="1"]').exists()).toBe(true);
    expect(wrapper.find('[data-test="new-kit"]').exists()).toBe(false);
    expect(wrapper.find('[data-test="kit-edit"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('came from Nova campanha (Gerenciar): a button goes back to the campaign draft', async () => {
    currentRoute.query = { from: 'campaign' };
    BrandKitsAPI.list.mockReturnValue(
      listResponse([kit(1, 'Hub2You', { is_default: true })])
    );
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-test="back-to-campaign"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_new',
      query: { returned: '1' },
    });
    wrapper.unmount();
  });

  it('shows the Campanhas and Identidade visual tabs, this one current', async () => {
    BrandKitsAPI.list.mockReturnValue(listResponse([]));
    const wrapper = mountPage();
    await flushPromises();

    expect(
      wrapper.find('[data-tab="identity"]').attributes('aria-current')
    ).toBe('page');
    expect(wrapper.find('[data-tab="campaigns"]').exists()).toBe(true);
    wrapper.unmount();
  });
});
