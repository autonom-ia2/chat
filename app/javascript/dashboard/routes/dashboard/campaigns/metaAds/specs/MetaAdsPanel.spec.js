import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsPanel from '../components/MetaAdsPanel.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const routing = vi.hoisted(() => ({
  route: { params: { accountId: '18' }, query: {} },
  replace: vi.fn(),
}));

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    panel: vi.fn(),
    panelAd: vi.fn(),
    dailyAction: vi.fn(),
    quoteMessage: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => routing.route,
  useRouter: () => ({ replace: routing.replace }),
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
const mountPanel = async (options = {}) => {
  mounted = mount(MetaAdsPanel, {
    ...options,
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
    // Rota reativa e replace que muda o endereço, como o vue-router: o painel lê o anúncio aberto do endereço.
    routing.route = reactive({ params: { accountId: '18' }, query: {} });
    routing.replace.mockImplementation(({ query }) => {
      routing.route.query = query;
    });
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue({ data: { ad: null } });
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: { daily_action: null },
    });
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
    const stalledStyle = () =>
      wrapper.find('[data-panel-stalled]').attributes('style') || '';
    expect(stalledStyle()).toContain('display: none');

    await wrapper.find('[data-panel-action-button]').trigger('click');
    expect(stalledStyle()).not.toContain('display: none');

    const card = wrapper.find('[data-panel-stalled-card]');
    expect(card.text()).toContain('Virgínia');
    expect(card.find('a').attributes('href')).toContain(
      '/app/accounts/18/conversations/99'
    );
  });

  it('the AI can point to an ad to review, and its button opens that ad', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: {
        daily_action: {
          source: 'ai',
          reason: null,
          kind: 'review_ad',
          ad_id: '1',
          headline: 'Revise o anúncio Capa.',
          body: null,
          why: 'Ele trouxe 12 conversas e nenhuma venda.',
          days: 30,
        },
      },
    });
    const wrapper = await mountPanel();

    expect(CrmMetaAdsConnectionAPI.dailyAction).toHaveBeenCalledWith(30);
    expect(
      wrapper.find('[data-panel-action]').attributes('data-action-kind')
    ).toBe('review_ad');
    await wrapper.find('[data-panel-action-button]').trigger('click');
    await flushPromises();

    expect(routing.replace).toHaveBeenCalledWith({ query: { anuncio: '1' } });
  });

  it('each stalled quote can get a suggested message', async () => {
    const wrapper = await mountPanel();

    await wrapper.find('[data-panel-action-button]').trigger('click');

    expect(
      wrapper.find('[data-panel-stalled-card] [data-quote-suggest]').exists()
    ).toBe(true);
  });

  it('closing and reopening the stalled list keeps what each suggested message did', async () => {
    const wrapper = await mountPanel();
    const toggle = () =>
      wrapper.find('[data-panel-action-button]').trigger('click');

    await toggle();
    const uid = () =>
      wrapper.findComponent({ name: 'MetaAdsQuoteMessage' }).vm.$.uid;
    const before = uid();
    await toggle();
    expect(wrapper.find('[data-panel-stalled]').attributes('style')).toContain(
      'display: none'
    );
    await toggle();

    expect(uid()).toBe(before);
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

  it('shows the ad image in its own format, or a placeholder without one', async () => {
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          ads: [
            { ...PANEL.ads[0], thumbnail_url: 'https://scontent/capa.jpg' },
            { ...PANEL.ads[0], ad_id: '2', thumbnail_url: null },
          ],
        },
      },
    });
    const wrapper = await mountPanel();

    const image = wrapper.find('[data-panel-ad="1"] [data-panel-ad-image]');
    expect(image.attributes('src')).toBe('https://scontent/capa.jpg');
    expect(image.classes()).toContain('h-auto');
    expect(
      wrapper.find('[data-panel-ad="2"] [data-panel-ad-placeholder]').exists()
    ).toBe(true);
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

  it('opens the ad from inside its card and keeps it in the address', async () => {
    const wrapper = await mountPanel();

    const open = wrapper.find('[data-panel-ad-open="1"]');
    expect(open.element.tagName).toBe('BUTTON');
    expect(open.classes()).toContain('min-h-11');
    await open.trigger('click');
    await flushPromises();

    expect(routing.replace).toHaveBeenCalledWith({ query: { anuncio: '1' } });
    expect(CrmMetaAdsConnectionAPI.panelAd).toHaveBeenCalledWith('1', 30);
    expect(wrapper.find('[data-ad-detail]').exists()).toBe(true);
    expect(wrapper.find('[data-panel-hero]').exists()).toBe(false);
    expect(wrapper.find('[data-panel-ad="1"]').exists()).toBe(false);
  });

  it('opens straight on the ad when the address has ?anuncio and goes back to the panel', async () => {
    routing.route.query = { aba: 'resultado', anuncio: '1' };
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-ad-detail]').exists()).toBe(true);
    expect(CrmMetaAdsConnectionAPI.panelAd).toHaveBeenCalledWith('1', 30);

    await wrapper.find('[data-ad-detail-back]').trigger('click');

    expect(routing.replace).toHaveBeenLastCalledWith({
      query: { aba: 'resultado' },
    });
    expect(wrapper.find('[data-ad-detail]').exists()).toBe(false);
    expect(wrapper.find('[data-panel-ad="1"]').exists()).toBe(true);
  });

  it('asks the open ad again for the new period', async () => {
    routing.route.query = { anuncio: '1' };
    const wrapper = await mountPanel();

    await wrapper.find('[data-panel-period="7"]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.panelAd).toHaveBeenLastCalledWith('1', 7);
  });

  it('closes the ad when the address loses ?anuncio, like the side menu to the same page', async () => {
    routing.route.query = { anuncio: '1' };
    const wrapper = await mountPanel();
    expect(wrapper.find('[data-ad-detail]').exists()).toBe(true);

    routing.route.query = {};
    await flushPromises();

    expect(wrapper.find('[data-ad-detail]').exists()).toBe(false);
    expect(wrapper.find('[data-panel-hero]').exists()).toBe(true);
  });

  it('gives the focus back to the card of the ad when coming back', async () => {
    const wrapper = await mountPanel({ attachTo: document.body });

    await wrapper.find('[data-panel-ad-open="1"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-ad-detail-back]').trigger('click');
    await flushPromises();

    expect(document.activeElement.getAttribute('data-panel-ad-open')).toBe('1');
  });
});
