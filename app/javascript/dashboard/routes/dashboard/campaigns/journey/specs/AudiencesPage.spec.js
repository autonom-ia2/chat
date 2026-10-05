import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import enImport from 'dashboard/i18n/locale/en/campaignImport.json';
import AudiencesPage from '../AudiencesPage.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
const alert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));
import { buildAudienceRow } from 'dashboard/components-next/CampaignJourney/audienceRows';

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const OLD_IMPORT = {
  id: 1,
  campaign_name: 'Auto outubro',
  source_filename: 'auto.xlsx',
  valid_rows: 98,
  total_rows: 100,
  status: 'completed',
  created_at: '2026-10-02T12:00:00Z',
};
const NEW_IMPORT = {
  id: 2,
  name: 'Corretoras parceiras',
  campaign_name: 'legacy name',
  source_filename: 'corretoras.csv',
  valid_rows: 1248,
  status: 'completed',
  created_at: '2026-10-05T12:00:00Z',
  channels: {
    email: { enabled: true, count: 1240 },
    whatsapp: { enabled: true, count: 980 },
  },
};

const DialogStub = {
  name: 'Dialog',
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div data-test="dialog"><button data-test="dialog-confirm" @click="$emit(\'confirm\')" /></div>',
};

const mountPage = (records, { customRole = null, remove = vi.fn() } = {}) => {
  const get = vi.fn();
  const store = createStore({
    getters: {
      getCurrentUser: () => ({
        accounts: [{ id: 1, permissions: customRole || [] }],
      }),
      getCurrentCustomRoleId: () => (customRole ? 7 : null),
      getCurrentAccountId: () => 1,
    },
    modules: {
      campaignImports: {
        namespaced: true,
        state: { records },
        getters: {
          getCampaignImports: state => state.records,
          getUIFlags: () => ({ isFetching: false, isCreating: false }),
          getMeta: state => ({ count: state.records.length }),
        },
        actions: { get, create: vi.fn(), delete: remove },
      },
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...enJourney, ...enImport } },
  });
  const wrapper = mount(AudiencesPage, {
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': { template: '<a><slot /></a>' },
        Dialog: DialogStub,
      },
    },
  });
  return { wrapper, get };
};

describe('Público page (PRD §6.6)', () => {
  it('loads the campaign imports and shows the empty state with one action', async () => {
    const { wrapper, get } = mountPage([]);
    await flushPromises();

    expect(get).toHaveBeenCalledTimes(1);
    const empty = wrapper.find('[data-test="audiences-empty"]');
    expect(empty.exists()).toBe(true);
    expect(empty.text()).toContain("You don't have an audience yet");
    expect(empty.text()).toContain('New audience');
  });

  it('renders channel badges with counts when the import has channels', async () => {
    const { wrapper } = mountPage([NEW_IMPORT]);
    await flushPromises();

    const row = wrapper.find('[data-audience="2"]');
    expect(row.text()).toContain('Corretoras parceiras');
    expect(row.text()).not.toContain('legacy name');
    expect(row.find('[data-badge="email"]').text()).toBe('Email · 1,240');
    expect(row.find('[data-badge="whatsapp"]').text()).toBe('WhatsApp · 980');
    expect(row.text()).toContain('1,248 people');
  });

  it('renders older imports without channels: campaign name, no badges, no crash', async () => {
    const { wrapper } = mountPage([OLD_IMPORT]);
    await flushPromises();

    const row = wrapper.find('[data-audience="1"]');
    expect(row.text()).toContain('Auto outubro');
    expect(row.find('[data-badge="email"]').exists()).toBe(false);
    expect(row.find('[data-badge="whatsapp"]').exists()).toBe(false);
    expect(row.find('[data-badge="none"]').text()).toBe(
      'Channels not calculated yet'
    );
    expect(row.text()).toContain('98 people');
  });
});

describe('Público actions (F2, F3, A4)', () => {
  const SAVED = { ...NEW_IMPORT, can_delete: true };

  it('"Novo público" opens its page and "Usar em nova campanha" opens Passo 1 with it', async () => {
    push.mockClear();
    const { wrapper } = mountPage([SAVED]);
    await flushPromises();

    await wrapper.find('[data-test="new-audience"]').trigger('click');
    expect(push).toHaveBeenLastCalledWith({
      name: 'campaigns_journey_audience_new',
    });
    await wrapper.find('[data-use="2"]').trigger('click');
    expect(push).toHaveBeenLastCalledWith({
      name: 'campaigns_journey_new',
      query: { audience: '2' },
    });
  });

  it('campaign_view only: no create, use or delete actions', async () => {
    const { wrapper } = mountPage([SAVED], { customRole: ['campaign_view'] });
    await flushPromises();

    expect(wrapper.find('[data-test="new-audience"]').exists()).toBe(false);
    expect(wrapper.find('[data-use="2"]').exists()).toBe(false);
    expect(wrapper.find('[data-delete="2"]').exists()).toBe(false);
    expect(wrapper.find('[data-audience="2"]').text()).toContain(
      'Corretoras parceiras'
    );
  });

  it('deleting an audience still in use names the campaigns', async () => {
    alert.mockClear();
    const remove = vi.fn().mockRejectedValue({
      response: {
        data: {
          code: 'audience_in_use',
          campaigns: [{ title: 'Renovação auto' }],
        },
      },
    });
    const { wrapper } = mountPage([SAVED], { remove });
    await flushPromises();

    await wrapper.find('[data-delete="2"]').trigger('click');
    await wrapper.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();

    expect(remove).toHaveBeenCalled();
    expect(alert).toHaveBeenCalledWith(
      expect.stringContaining('Renovação auto')
    );
  });
});

describe('buildAudienceRow', () => {
  it('hides switched-off or empty channels and tolerates malformed data', () => {
    expect(
      buildAudienceRow({
        ...NEW_IMPORT,
        channels: {
          email: { enabled: false, count: 10 },
          whatsapp: { enabled: true, count: 0 },
        },
      }).badges
    ).toEqual([]);
    expect(buildAudienceRow({ ...NEW_IMPORT, channels: [] }).badges).toEqual(
      []
    );
    expect(buildAudienceRow({ ...NEW_IMPORT, channels: {} }).badges).toEqual(
      []
    );
  });
});
