import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import enImport from 'dashboard/i18n/locale/en/campaignImport.json';
import AudiencesPage from '../AudiencesPage.vue';
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

const mountPage = records => {
  const get = vi.fn();
  const store = createStore({
    getters: {
      getCurrentUser: () => ({ accounts: [{ id: 1, permissions: [] }] }),
      getCurrentCustomRoleId: () => null,
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
        actions: { get, create: vi.fn() },
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
        CampaignImportDialog: true,
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
