import { reactive } from 'vue';
import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import MetaAdsPanel from '../components/MetaAdsPanel.vue';
import MetaAdsConfidence from '../components/MetaAdsConfidence.vue';
import confidenceSource from '../components/MetaAdsConfidence.vue?raw';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';
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
    panelList: vi.fn(),
    dailyAction: vi.fn(),
    openAdvice: vi.fn(),
    acceptAdvice: vi.fn(),
    dismissAdvice: vi.fn(),
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
  advice: {
    run_id: 812,
    local_date: '2026-10-07',
    rules_version: 'f5.1',
    writer: { status: 'rule', reason: null },
    actions: [
      {
        id: 11,
        position: 1,
        kind: 'stalled_quotes',
        variant: null,
        status: 'open',
        opened: false,
        ad_id: null,
        ad_name: 'Capa (1080x1350)',
        facts: {
          count: 2,
          value: 1464.64,
          days: 3,
          ad_name: 'Capa (1080x1350)',
        },
        button: { target: 'stalled_list', step: null, url: null },
        source: 'rule',
        headline: null,
        body: null,
        why: null,
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
    ],
  },
  response_time: {
    days: 30,
    median_seconds: 360,
    answered: 38,
    unanswered: 3,
    slow: 9,
    target_seconds: 300,
  },
  meta_comparison: null,
  confidence: {
    window_days: 30,
    conversations: 9,
    ad: 1,
    ad_name: 8,
    campaign: 0,
    unknown: 0,
  },
};

const [STALLED_ACTION] = PANEL.advice.actions;
const panelWith = actions =>
  CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
    data: { panel: { ...PANEL, advice: { ...PANEL.advice, actions } } },
  });

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
    CrmMetaAdsConnectionAPI.panelList.mockResolvedValue({
      data: { list: { step: 'quotes', days: 30, total: 0, items: [] } },
    });
    CrmMetaAdsConnectionAPI.openAdvice.mockResolvedValue({ data: {} });
    CrmMetaAdsConnectionAPI.dismissAdvice.mockResolvedValue({ data: {} });
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

  it('an ad to review opens that ad and records the opening', async () => {
    panelWith([
      {
        ...STALLED_ACTION,
        id: 41,
        kind: 'review_ad',
        variant: 'no_sales',
        ad_id: '1',
        button: { target: 'ad_detail', step: null, url: null },
        cards: [],
      },
    ]);
    const wrapper = await mountPanel();

    expect(
      wrapper.find('[data-panel-action]').attributes('data-action-kind')
    ).toBe('review_ad');
    await wrapper.find('[data-panel-action-button]').trigger('click');
    await flushPromises();

    expect(routing.replace).toHaveBeenCalledWith({ query: { anuncio: '1' } });
    expect(CrmMetaAdsConnectionAPI.openAdvice).toHaveBeenCalledWith(41);
  });

  it('slow replies open the slowest conversations of 30 days, even on 7', async () => {
    panelWith([
      {
        ...STALLED_ACTION,
        id: 42,
        kind: 'slow_response',
        button: { target: 'slow_replies', step: null, url: null },
        cards: [],
      },
    ]);
    const wrapper = await mountPanel();
    await wrapper.find('[data-panel-period="7"]').trigger('click');
    await flushPromises();

    const button = wrapper.find('[data-panel-action-button]');
    await button.trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.panelList).toHaveBeenCalledWith(
      'slow_replies',
      30
    );
    expect(
      wrapper.find('[data-panel-path-list]').attributes('data-path-list-step')
    ).toBe('slow_replies');
    expect(button.attributes('aria-expanded')).toBe('true');

    await button.trigger('click');
    expect(wrapper.find('[data-panel-path-list]').exists()).toBe(false);
  });

  it('dismissing an action asks the panel again for the next one', async () => {
    const wrapper = await mountPanel();
    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledTimes(1);

    await wrapper.find('[data-action-dismiss]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.dismissAdvice).toHaveBeenCalledWith(11);
    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledTimes(2);
  });

  it('checks again in 20 seconds while the AI is writing in another tab', async () => {
    vi.useFakeTimers();
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          advice: { ...PANEL.advice, writer: { status: 'writing' } },
        },
      },
    });
    await mountPanel();
    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(20 * 1000);
    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledTimes(2);
  });

  it('does not check again in 20 seconds when nothing is being written', async () => {
    vi.useFakeTimers();
    await mountPanel();

    await vi.advanceTimersByTimeAsync(20 * 1000);
    expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledTimes(1);
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
    panelWith([
      {
        ...STALLED_ACTION,
        id: 43,
        kind: 'fix_tracking',
        facts: { conversations: 9, unknown: 6, identified_pct: 0.33 },
        button: { target: 'connection_step', step: 3, url: null },
        cards: [],
      },
    ]);
    const wrapper = await mountPanel();

    await wrapper.find('[data-panel-action-button]').trigger('click');

    expect(wrapper.emitted('open')).toEqual([[3]]);
  });

  it('wait has no button and no stalled list', async () => {
    panelWith([
      {
        ...STALLED_ACTION,
        id: null,
        kind: 'wait',
        status: null,
        ad_id: '1',
        facts: { ad_name: 'Capa', missing_conversations: 8 },
        button: { target: 'none', step: null, url: null },
        cards: [],
      },
    ]);
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-panel-action-button]').exists()).toBe(false);
    expect(wrapper.find('[data-panel-stalled]').exists()).toBe(false);
    expect(wrapper.find('[data-panel-stalled-button]').exists()).toBe(false);
  });

  it('opens and closes the list of each step, one at a time, in the period of the screen', async () => {
    const wrapper = await mountPanel();
    const open = step => wrapper.find(`[data-panel-path-open="${step}"]`);

    expect(wrapper.find('[data-panel-path-open="SPEND"]').exists()).toBe(false);
    expect(open('quotes').attributes('aria-expanded')).toBe('false');
    expect(open('quotes').classes()).toContain('min-h-11');

    await open('quotes').trigger('click');
    await flushPromises();
    expect(CrmMetaAdsConnectionAPI.panelList).toHaveBeenLastCalledWith(
      'quotes',
      30
    );
    expect(open('quotes').attributes('aria-expanded')).toBe('true');
    expect(wrapper.findAll('[data-panel-path-list]')).toHaveLength(1);

    await open('sales').trigger('click');
    await flushPromises();
    expect(CrmMetaAdsConnectionAPI.panelList).toHaveBeenLastCalledWith(
      'sales',
      30
    );
    expect(open('quotes').attributes('aria-expanded')).toBe('false');
    expect(wrapper.findAll('[data-panel-path-list]')).toHaveLength(1);

    await open('sales').trigger('click');
    expect(wrapper.find('[data-panel-path-list]').exists()).toBe(false);
    expect(routing.replace).not.toHaveBeenCalled();
  });

  it('shows the response time on the conversations step, amber above 5 minutes', async () => {
    const wrapper = await mountPanel();

    const response = wrapper.find(
      '[data-panel-path="CONVERSATIONS"] [data-panel-response-time]'
    );
    expect(response.text()).toContain('PANEL.RESPONSE_TIME.LABEL');
    expect(response.text()).toContain('PANEL.DURATION.MINUTES');
    expect(
      response.find('[data-panel-response-time-value]').classes()
    ).toContain('text-n-amber-11');
    expect(
      response.find('[data-panel-response-time-unanswered]').text()
    ).toContain('RESPONSE_TIME.UNANSWERED');
  });

  it('hides the response time without a measured answer, and the unanswered note without one', async () => {
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          response_time: {
            ...PANEL.response_time,
            median_seconds: 120,
            unanswered: 0,
          },
        },
      },
    });
    const fast = await mountPanel();
    const response = fast.find('[data-panel-response-time]');
    expect(
      response.find('[data-panel-response-time-value]').classes()
    ).not.toContain('text-n-amber-11');
    expect(
      response.find('[data-panel-response-time-unanswered]').exists()
    ).toBe(false);
    fast.unmount();

    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          response_time: { ...PANEL.response_time, median_seconds: null },
        },
      },
    });
    const none = await mountPanel();
    expect(none.find('[data-panel-response-time]').exists()).toBe(false);
  });

  it('gives "How much to trust" the period of the screen and the Meta comparison', async () => {
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          meta_comparison: {
            days: 30,
            until: '2026-10-06',
            rows: [
              {
                destination: 'whatsapp',
                meta: 52,
                ours: 46,
                difference: -6,
                explanation: 'close',
              },
            ],
            explanation: null,
          },
        },
      },
    });
    const wrapper = await mountPanel();

    const confidence = wrapper.find('[data-summary-confidence]');
    expect(confidence.text()).toContain('CONFIDENCE.TITLE_PERIOD {"days":30}');
    expect(
      confidence
        .find('[data-confidence-meta-row="whatsapp"]')
        .attributes('data-confidence-meta-explanation')
    ).toBe('close');
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

  it('swaps an image that does not load (expired Meta link) for the placeholder', async () => {
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({
      data: {
        panel: {
          ...PANEL,
          ads: [
            { ...PANEL.ads[0], thumbnail_url: 'https://scontent/capa.jpg' },
          ],
        },
      },
    });
    const wrapper = await mountPanel();

    await wrapper
      .find('[data-panel-ad="1"] [data-panel-ad-image]')
      .trigger('error');

    expect(
      wrapper.find('[data-panel-ad="1"] [data-panel-ad-image]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-panel-ad="1"] [data-panel-ad-placeholder]').exists()
    ).toBe(true);
  });

  it('shows the image again when the panel brings a new link after a failure', async () => {
    const withImage = url => ({
      data: {
        panel: {
          ...PANEL,
          ads: [{ ...PANEL.ads[0], thumbnail_url: url }],
        },
      },
    });
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue(
      withImage('https://scontent/old.jpg')
    );
    const wrapper = await mountPanel();
    await wrapper
      .find('[data-panel-ad="1"] [data-panel-ad-image]')
      .trigger('error');

    CrmMetaAdsConnectionAPI.panel.mockResolvedValue(
      withImage('https://scontent/new.jpg')
    );
    emitter.emit(BUS_EVENTS.CRM_META_ADS_INSIGHTS_UPDATED, { account_id: 18 });
    await flushPromises();

    expect(
      wrapper
        .find('[data-panel-ad="1"] [data-panel-ad-image]')
        .attributes('src')
    ).toBe('https://scontent/new.jpg');
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

// "Quanto confiar" com o catálogo real (#1110, F5, §5.2): os números entram por slot do <I18nT>, em negrito,
// sem v-html. O i18n vazio do setup dá lugar ao real só neste bloco.
describe('Anúncios da Meta · Quanto confiar, Meta × nós (#1110, F5)', () => {
  const CONFIDENCE = PANEL.confidence;
  const ROWS = [
    {
      destination: 'whatsapp',
      meta: 52,
      ours: 46,
      difference: -6,
      explanation: 'close',
    },
    {
      destination: 'site',
      meta: 12,
      meta_visits: 31,
      ours: 3,
      difference: -9,
      explanation: 'meta_higher',
    },
  ];
  let savedPlugins;

  beforeEach(() => {
    savedPlugins = config.global.plugins;
    config.global.plugins = [
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        messages: { en, pt_BR: ptBR },
        missingWarn: false,
        fallbackWarn: false,
      }),
    ];
  });

  afterEach(() => {
    config.global.plugins = savedPlugins;
  });

  const mountConfidence = props => mount(MetaAdsConfidence, { props });

  it('shows one line per destination with the numbers in bold and the explanation below', () => {
    const wrapper = mountConfidence({
      confidence: CONFIDENCE,
      comparison: { days: 30, until: '2026-10-06', rows: ROWS },
    });

    expect(wrapper.find('h4').text()).toBe(
      'Quanto confiar nos números — últimos 30 dias'
    );
    const whatsapp = wrapper.find('[data-confidence-meta-row="whatsapp"]');
    expect(whatsapp.text()).toContain(
      'Até ontem, a Meta diz 52 conversas iniciadas pelo WhatsApp; nós contamos 46.'
    );
    expect(whatsapp.findAll('strong').map(node => node.text())).toEqual([
      '52',
      '46',
    ]);
    expect(whatsapp.text()).toContain('Os dois números batem.');
    const site = wrapper.find('[data-confidence-meta-row="site"]');
    expect(site.text()).toContain(
      '12 contatos pelo site (visitas à página: 31); pelo botão do site, nós contamos 3.'
    );
    expect(site.text()).toContain('nem todo mundo clica depois');
  });

  it('says when Meta has not sent the number yet', () => {
    const wrapper = mountConfidence({
      confidence: CONFIDENCE,
      comparison: { days: 7, rows: [], explanation: 'no_meta_data' },
    });

    expect(wrapper.find('[data-confidence-meta-empty]').text()).toBe(
      'A Meta ainda não mandou o número deste período.'
    );
  });

  // meta = 0: o servidor manda a linha sem explicação; "batem" ao lado de "a Meta ainda não mandou" se contradiz.
  it('a line without a Meta number shows no explanation, only the notice', () => {
    const wrapper = mountConfidence({
      confidence: CONFIDENCE,
      comparison: {
        days: 7,
        rows: [
          {
            destination: 'site',
            meta: 0,
            meta_visits: 0,
            ours: 1,
            difference: 1,
            explanation: null,
          },
        ],
        explanation: 'no_meta_data',
      },
    });

    const site = wrapper.find('[data-confidence-meta-row="site"]');
    expect(site.text()).toBe(
      'Até ontem, a Meta diz 0 contatos pelo site (visitas à página: 0); pelo botão do site, nós contamos 1.'
    );
    expect(site.findAll('p')).toHaveLength(1);
    expect(wrapper.find('[data-confidence-meta-empty]').exists()).toBe(true);
  });

  it('without the comparison it stays as before (the Connection tab)', () => {
    const wrapper = mountConfidence({ confidence: CONFIDENCE });

    expect(wrapper.find('h4').text()).toBe('Quanto confiar nos números');
    expect(wrapper.find('[data-confidence-meta]').exists()).toBe(false);
  });

  it('in the panel without any line it keeps the period and shows no Meta line', () => {
    const wrapper = mountConfidence({
      confidence: CONFIDENCE,
      comparison: null,
    });

    expect(wrapper.find('h4').text()).toContain('últimos 30 dias');
    expect(wrapper.find('[data-confidence-meta]').exists()).toBe(false);
  });

  it('never renders HTML from the messages', () => {
    const template = confidenceSource.slice(
      confidenceSource.indexOf('<template>')
    );
    expect(template).toContain('<I18nT');
    expect(template).not.toContain('v-html');
  });
});
