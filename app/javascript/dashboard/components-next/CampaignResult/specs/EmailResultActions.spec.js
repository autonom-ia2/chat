import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/emailCampaignTemplates', () => ({
  default: { create: vi.fn() },
}));
const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const { default: EmailResultActions } = await import(
  '../EmailResultActions.vue'
);

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const mountActions = (campaign, { compact = false, customRole } = {}) => {
  const actions = {
    duplicate: vi.fn(() => ({ id: 77 })),
    pause: vi.fn(),
    cancel: vi.fn(),
    delete: vi.fn(),
  };
  const store = createStore({
    getters: {
      getCurrentUser: () => ({
        accounts: [{ id: 1, permissions: customRole || [] }],
      }),
      getCurrentCustomRoleId: () => (customRole ? 7 : null),
      getCurrentAccountId: () => 1,
    },
    modules: { emailCampaigns: { namespaced: true, actions } },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: enResult },
  });
  const wrapper = mount(EmailResultActions, {
    props: { campaign, compact },
    global: {
      plugins: [store, i18n],
      stubs: {
        Dialog: {
          template: '<div><slot /></div>',
          methods: { open() {}, close() {} },
        },
      },
    },
  });
  return { wrapper, actions };
};

describe('e-mail campaign actions (#1007, L8)', () => {
  it('from the list: the same actions behind the "more" button', async () => {
    const { wrapper, actions } = mountActions(
      { id: 9, name: 'Novidades', status: 'paused', body_html: '<p>Oi</p>' },
      { compact: true }
    );

    expect(wrapper.find('[data-action]').exists()).toBe(false);
    await wrapper.find('[data-actions-menu]').trigger('click');
    expect(
      wrapper
        .findAll('[data-action]')
        .map(item => item.attributes('data-action'))
    ).toEqual(['duplicate', 'template', 'cancel']);

    await wrapper.find('[data-action="duplicate"]').trigger('click');
    await flushPromises();
    expect(actions.duplicate).toHaveBeenCalled();
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_email_builder',
      params: { campaignId: 77 },
    });
  });

  it('nothing while the recipient import runs, and nothing for campaign_view', () => {
    const importing = mountActions({
      id: 9,
      status: 'draft',
      recipient_import: { status: 'processing' },
    }).wrapper;
    expect(
      importing
        .findAll('[data-action]')
        .map(item => item.attributes('data-action'))
    ).toEqual(['edit', 'duplicate']);

    const viewer = mountActions(
      { id: 9, status: 'sending' },
      { customRole: ['campaign_view'] }
    ).wrapper;
    expect(viewer.find('[data-email-actions]').exists()).toBe(false);
  });
});
