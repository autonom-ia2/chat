import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enBrand from 'dashboard/i18n/locale/en/brandKits.json';
import BrandKitsAPI from 'dashboard/api/brandKits';
import { resetBrandKits } from '../useBrandKits';
import BrandIdentityPicker from '../BrandIdentityPicker.vue';
import BrandIdentityLine from '../BrandIdentityLine.vue';
import BrandKitNudge from '../BrandKitNudge.vue';

vi.mock('dashboard/api/brandKits', () => ({ default: { list: vi.fn() } }));
const push = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push, resolve: () => ({ href: '/identity' }) }),
}));

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const palettes = {
  light: { primary: '#c8102e', band: '#0b243f' },
  dark: { primary: '#ff1f2d', band: '#0b243f' },
};
const kits = [
  { id: 1, name: 'Hub2You', is_default: true, appearance: { palettes } },
  { id: 2, name: 'Autonomia', is_default: false, appearance: { palettes } },
];

const mountWith = (component, props = {}, { emailConnected = true } = {}) => {
  const module = getters => ({ namespaced: true, getters });
  const store = createStore({
    getters: {
      getCurrentUser: () => ({ accounts: [{ id: 1, permissions: [] }] }),
      getCurrentCustomRoleId: () => null,
      getCurrentAccountId: () => 1,
    },
    modules: {
      inboxes: module({ getInboxes: () => [] }),
      emailSenderIdentities: module({
        getIdentities: () =>
          emailConnected ? [{ id: 1, status: 'verified' }] : [],
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
    locale: 'en',
    messages: { en: enBrand },
  });
  return mount(component, {
    props,
    attachTo: document.body,
    global: { plugins: [store, i18n] },
  });
};

const listResponse = payload =>
  Promise.resolve({
    data: { payload, meta: { archived_count: 0, google_fonts: [] } },
  });

describe('choosing the identity of an e-mail (#1076)', () => {
  beforeEach(() => {
    resetBrandKits();
    push.mockClear();
    BrandKitsAPI.list.mockReturnValue(listResponse(kits));
  });

  it('"Criar com IA" starts with the default identity; Trocar lists the others and another website', async () => {
    const wrapper = mountWith(BrandIdentityPicker, {
      modelValue: {
        kitId: null,
        importId: null,
        proposal: null,
        mode: 'light',
        saveAsKit: false,
      },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('Hub2You');
    await wrapper.find('[data-test="identity-change"]').trigger('click');
    await wrapper.find('[data-kit-option="2"]').trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toMatchObject({
      kitId: 2,
      importId: null,
    });

    await wrapper.find('[data-test="identity-change"]').trigger('click');
    await wrapper.find('[data-test="identity-other-site"]').trigger('click');
    expect(wrapper.find('[data-test="identity-site"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('shows the new identity once the site was saved as one', async () => {
    const wrapper = mountWith(BrandIdentityPicker, {
      modelValue: {
        kitId: null,
        importId: 9,
        proposal: { name: 'Aurora' },
        mode: 'light',
        saveAsKit: true,
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-test="identity-site"]').exists()).toBe(true);

    await wrapper.setProps({
      modelValue: {
        kitId: 2,
        importId: null,
        proposal: null,
        mode: 'light',
        saveAsKit: false,
      },
    });

    expect(wrapper.find('[data-test="identity-site"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Autonomia');
    wrapper.unmount();
  });

  it('the e-mail picks the light (recommended) or the dark version', async () => {
    const wrapper = mountWith(BrandIdentityPicker, {
      modelValue: {
        kitId: 1,
        importId: null,
        proposal: null,
        mode: 'light',
        saveAsKit: false,
      },
    });
    await flushPromises();

    expect(
      wrapper.find('[data-identity-mode="light"]').attributes('aria-checked')
    ).toBe('true');
    await wrapper.find('[data-identity-mode="dark"]').trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toMatchObject({
      mode: 'dark',
    });
    wrapper.unmount();
  });

  it('Nova campanha shows "Identity: Hub2You (default) · Change · Manage"', async () => {
    const wrapper = mountWith(BrandIdentityLine, { kitId: null });
    await flushPromises();

    expect(wrapper.find('[data-test="identity-line"]').text()).toContain(
      'Identity:'
    );
    expect(wrapper.text()).toContain('Hub2You');
    expect(wrapper.text()).toContain('(default)');
    await wrapper.find('[data-test="identity-line-manage"]').trigger('click');
    expect(wrapper.emitted('manage')[0]).toEqual([false]);
    wrapper.unmount();
  });

  it('the campaign list invites to create the first identity, only when there is none', async () => {
    BrandKitsAPI.list.mockReturnValue(listResponse([]));
    const wrapper = mountWith(BrandKitNudge);
    await flushPromises();

    expect(wrapper.find('[data-test="brand-nudge"]').text()).toContain(
      "Your e-mails don't look like your brand yet."
    );
    await wrapper.find('[data-test="brand-nudge-action"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_brand_kit_new',
    });
    wrapper.unmount();
  });

  it('nothing about identity when the account has no e-mail connected', async () => {
    BrandKitsAPI.list.mockReturnValue(listResponse([]));
    const wrapper = mountWith(BrandKitNudge, {}, { emailConnected: false });
    await flushPromises();

    expect(wrapper.find('[data-test="brand-nudge"]').exists()).toBe(false);
    expect(BrandKitsAPI.list).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
