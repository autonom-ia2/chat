import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsPanel from '../components/MetaAdsPanel.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { panel: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' } }),
}));

const PANEL = {
  days: 30,
  currency: 'BRL',
  synced_at: new Date().toISOString(),
  refreshing: false,
  totals: {
    spend: 373.86,
    conversations: 54,
    quotes: 9,
    open_quotes: 9,
    sales: 0,
    sales_value: 0,
    cost_per_conversation: 6.92,
    cost_per_sale: null,
    return_per_real: null,
  },
  ads: [
    {
      ad_id: '1',
      name: 'Capa (1080x1350)',
      thumbnail_url: null,
      spend: 163.51,
      conversations: 12,
      quotes: 4,
      sales: 0,
      cost_per_sale: null,
      verdict: 'early',
    },
  ],
  action: {
    kind: 'stalled_quotes',
    count: 2,
    value: 1464.64,
    days: 3,
    ad_name: 'Capa (1080x1350)',
    cards: [
      {
        id: 7,
        title: 'Virgínia',
        value: 842,
        conversation_id: 99,
        waiting_since: '2026-10-01T10:00:00Z',
      },
    ],
  },
  confidence: {
    window_days: 30,
    conversations: 9,
    ad: 1,
    ad_name: 8,
    campaign: 0,
    unknown: 0,
  },
};

let mounted = null;
const mountPanel = async () => {
  mounted = mount(MetaAdsPanel, {
    global: {
      mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
      stubs: {
        Spinner: true,
        RouterLink: {
          props: ['to'],
          template: '<a :href="to"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return mounted;
};

describe('Anúncios da Meta · painel do dia a dia (#1088)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: { panel: PANEL },
    });
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    vi.useRealTimers();
  });

  it('tells the money story in one sentence and shows the path', async () => {
    const wrapper = await mountPanel();

    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledWith(30);
    expect(wrapper.find('[data-panel-headline]').text()).toContain(
      'PANEL.HEADLINE'
    );
    expect(wrapper.find('[data-panel-path="CONVERSATIONS"]').text()).toContain(
      '54'
    );
    expect(wrapper.find('[data-panel-path="QUOTES"]').text()).toContain('9');
  });

  it('shows the action of the day and opens the stalled quotes with a link to the conversation', async () => {
    const wrapper = await mountPanel();

    expect(
      wrapper.find('[data-panel-action]').attributes('data-action-kind')
    ).toBe('stalled_quotes');
    expect(wrapper.find('[data-panel-stalled]').exists()).toBe(false);

    await wrapper.find('[data-panel-action-button]').trigger('click');

    const card = wrapper.find('[data-panel-stalled-card]');
    expect(card.text()).toContain('Virgínia');
    expect(card.find('a').attributes('href')).toContain(
      '/app/accounts/18/conversations/99'
    );
  });

  it('fix tracking sends the person to step 3', async () => {
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          action: { kind: 'fix_tracking', conversations: 9, unknown: 6 },
        },
      },
    });
    const wrapper = await mountPanel();

    await wrapper.find('[data-panel-action-button]').trigger('click');

    expect(wrapper.emitted('open')).toEqual([[3]]);
  });

  it('wait has no button', async () => {
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          action: { kind: 'wait', ad_name: 'Capa', missing_conversations: 8 },
        },
      },
    });
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-panel-action-button]').exists()).toBe(false);
  });

  it('shows each ad with its verdict in words', async () => {
    const wrapper = await mountPanel();

    const ad = wrapper.find('[data-panel-ad="1"]');
    expect(ad.text()).toContain('Capa (1080x1350)');
    expect(ad.find('[data-verdict]').text()).toContain('VERDICT.EARLY');
  });

  it('changes the period and asks again', async () => {
    const wrapper = await mountPanel();

    await wrapper.find('[data-panel-period="7"]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenLastCalledWith(7);
    expect(
      wrapper.find('[data-panel-period="7"]').attributes('aria-pressed')
    ).toBe('true');
  });

  it('drops the answer of a period that is no longer chosen', async () => {
    const wrapper = await mountPanel();
    let slow;
    CrmMetaAdsConnectionAPI.panel
      .mockReturnValueOnce(
        new Promise(resolve => {
          slow = resolve;
        })
      )
      .mockResolvedValueOnce({
        data: {
          panel: { ...PANEL, days: 30, totals: { ...PANEL.totals, spend: 1 } },
        },
      });

    await wrapper.find('[data-panel-period="7"]').trigger('click');
    await wrapper.find('[data-panel-period="30"]').trigger('click');
    await flushPromises();
    slow({
      data: {
        panel: { ...PANEL, days: 7, totals: { ...PANEL.totals, spend: 999 } },
      },
    });
    await flushPromises();

    expect(wrapper.find('[data-panel-path="SPEND"]').text()).toContain('1');
    expect(wrapper.find('[data-panel-path="SPEND"]').text()).not.toContain(
      '999'
    );
  });

  it('reloads on the realtime event and every 2 minutes while open', async () => {
    vi.useFakeTimers();
    await mountPanel();

    emitter.emit(BUS_EVENTS.CRM_META_ADS_INSIGHTS_UPDATED, {
      account_id: 18,
    });
    await flushPromises();
    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledTimes(2);

    await vi.advanceTimersByTimeAsync(2 * 60 * 1000);
    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledTimes(3);
  });
});
