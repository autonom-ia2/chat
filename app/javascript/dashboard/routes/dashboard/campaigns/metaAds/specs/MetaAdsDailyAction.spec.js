import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import MetaAdsDailyAction from '../components/MetaAdsDailyAction.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    dailyAction: vi.fn(),
    openAdvice: vi.fn(),
    acceptAdvice: vi.fn(),
    dismissAdvice: vi.fn(),
  },
}));

const ACTION_KEY = 'CRM_KANBAN.META_ADS_HUB.PANEL.ACTION';

const STALLED = {
  id: 11,
  position: 1,
  kind: 'stalled_quotes',
  variant: null,
  status: 'open',
  opened: false,
  ad_id: null,
  ad_name: 'Promo outubro',
  facts: { count: 4, value: 6200, days: 3, ad_name: 'Promo outubro' },
  button: { target: 'stalled_list', step: null, url: null },
  source: 'rule',
  headline: null,
  body: null,
  why: null,
  cards: [],
};
const SLOW = {
  ...STALLED,
  id: 12,
  position: 2,
  kind: 'slow_response',
  ad_name: null,
  facts: {
    median_seconds: 1500,
    answered: 12,
    unanswered: 2,
    target_seconds: 300,
    window_days: 30,
  },
  button: { target: 'slow_replies', step: null, url: null },
  source: 'ai',
  headline: 'Responda as conversas de anúncio mais rápido.',
  body: 'Quem espera procura outro.',
  why: 'Metade esperou mais de 25 min.',
};
const FIX = {
  ...STALLED,
  id: 13,
  position: 3,
  kind: 'fix_tracking',
  ad_name: null,
  facts: { conversations: 29, unknown: 9, identified_pct: 0.69 },
  button: { target: 'connection_step', step: 3, url: null },
};
const SCALE = {
  ...STALLED,
  id: 21,
  kind: 'scale_ad',
  ad_id: 'C',
  ad_name: 'Promo C',
  facts: {
    ad_name: 'Promo C',
    cost_per_sale: 120,
    target_cost_per_sale: 150,
    frequency_7d: 2.1,
    max_increase_pct: 0.2,
    weeks: 2,
    cooldown_days: 3,
  },
  button: {
    target: 'ads_manager',
    step: null,
    url: 'https://adsmanager.facebook.com/adsmanager/manage/ads?act=9001&selected_ad_ids=C',
  },
};
const AUCTION = {
  ...STALLED,
  id: 31,
  kind: 'auction_pressure',
  ad_name: null,
  facts: {
    cpm_change_pct: 0.4,
    cpm_recent: 28,
    cpm_baseline: 20,
    window_days: 7,
  },
  button: { target: 'acknowledge', step: null, url: null },
};
const ON_TRACK = {
  ...STALLED,
  id: null,
  kind: 'on_track',
  status: null,
  facts: {},
  button: { target: 'none', step: null, url: null },
};

const advice = (actions, writer = { status: 'rule', reason: null }) => ({
  run_id: 812,
  local_date: '2026-10-07',
  rules_version: 'f5.1',
  writer,
  actions,
});

let mounted = null;
const mountAction = async (props = {}, options = {}) => {
  mounted = mount(MetaAdsDailyAction, {
    props: { advice: advice([STALLED, SLOW, FIX]), days: 30, ...props },
    global: {
      mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
      ...options,
    },
  });
  await flushPromises();
  return mounted;
};

const item = (wrapper, id) => wrapper.find(`[data-action-id="${id}"]`);

// O catálogo real só deste módulo, no lugar do i18n vazio do setup, para conferir os fatos formatados no texto
// da regra. Devolve o setup ao fim do exemplo.
let savedPlugins = null;
const useRealI18n = locale => {
  savedPlugins = config.global.plugins;
  config.global.plugins = [
    createI18n({
      legacy: false,
      locale,
      messages: { en, pt_BR: ptBR },
      missingWarn: false,
      fallbackWarn: false,
    }),
  ];
};

describe('Anúncios da Meta · o que fazer hoje, até 3 ações (#1110, F5)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.openAdvice.mockResolvedValue({ data: {} });
    CrmMetaAdsConnectionAPI.acceptAdvice.mockResolvedValue({ data: {} });
    CrmMetaAdsConnectionAPI.dismissAdvice.mockResolvedValue({ data: {} });
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    if (savedPlugins) config.global.plugins = savedPlugins;
    savedPlugins = null;
  });

  it('shows the 3 actions in the server order, AI text where there is one and the rule on the others', async () => {
    const wrapper = await mountAction();

    const items = wrapper.findAll('[data-panel-actions] [data-panel-action]');
    expect(items.map(li => li.attributes('data-action-kind'))).toEqual([
      'stalled_quotes',
      'slow_response',
      'fix_tracking',
    ]);
    expect(items.map(li => li.attributes('data-action-source'))).toEqual([
      'rule',
      'ai',
      'rule',
    ]);
    expect(items[0].find('[data-daily-text]').text()).toBe(
      `${ACTION_KEY}.STALLED_QUOTES.TEXT`
    );
    expect(items[1].find('[data-daily-text]').text()).toBe(SLOW.headline);
    expect(items[1].find('[data-daily-why]').text()).toContain(SLOW.why);
    expect(items[1].find('[data-daily-why-label]').exists()).toBe(true);
    // Corpo só na primeira ação; as outras são compactas.
    expect(items[1].find('[data-daily-body]').exists()).toBe(false);
    expect(wrapper.findAll('[data-daily-ai-badge]')).toHaveLength(1);
    expect(CrmMetaAdsConnectionAPI.dailyAction).not.toHaveBeenCalled();
  });

  it('writes the rule text with the facts formatted by type (pt_BR)', async () => {
    useRealI18n('pt_BR');
    const wrapper = await mountAction({
      advice: advice([
        { ...SLOW, source: 'rule', headline: null, why: null },
        SCALE,
      ]),
      currency: 'BRL',
    });

    const slow = item(wrapper, 12);
    expect(slow.find('[data-daily-text]').text()).toContain(
      'esperou mais de 25 min pela resposta, e 2 ficaram sem resposta'
    );
    expect(slow.find('[data-daily-why]').text()).toContain(
      'responder em até 5 min'
    );
    const scale = item(wrapper, 21);
    expect(scale.find('[data-daily-text]').text()).toBe(
      'Aumente o orçamento de "Promo C" em até 20%.'
    );
    expect(scale.find('[data-daily-why]').text()).toMatch(
      /R\$\s120.*R\$\s150.*há 2 semanas.*espere 3 dias/
    );
  });

  it('the main button goes to the work and records the opening once', async () => {
    const wrapper = await mountAction();

    const button = item(wrapper, 11).find('[data-panel-action-button]');
    expect(button.classes()).toContain('min-h-11');
    await button.trigger('click');
    await flushPromises();
    await button.trigger('click');
    await flushPromises();

    expect(wrapper.emitted('act')).toHaveLength(2);
    expect(wrapper.emitted('act')[0][0]).toMatchObject({
      id: 11,
      button: { target: 'stalled_list' },
    });
    expect(CrmMetaAdsConnectionAPI.openAdvice).toHaveBeenCalledTimes(1);
    expect(CrmMetaAdsConnectionAPI.openAdvice).toHaveBeenCalledWith(11);
    expect(CrmMetaAdsConnectionAPI.acceptAdvice).not.toHaveBeenCalled();
  });

  it('does not record the opening again for an action already opened', async () => {
    const wrapper = await mountAction({
      advice: advice([{ ...FIX, opened: true }]),
    });

    await item(wrapper, 13).find('[data-panel-action-button]').trigger('click');

    expect(wrapper.emitted('act')[0][0].button.step).toBe(3);
    expect(CrmMetaAdsConnectionAPI.openAdvice).not.toHaveBeenCalled();
  });

  it('a failed opening goes to the console and does not hold the person', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    CrmMetaAdsConnectionAPI.openAdvice.mockRejectedValue(new TypeError('x'));
    const wrapper = await mountAction();

    await item(wrapper, 11).find('[data-panel-action-button]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('act')).toHaveLength(1);
    expect(error).toHaveBeenCalledWith(
      '[meta-ads] openAdvice failed',
      'TypeError'
    );
    expect(useAlert).not.toHaveBeenCalled();
    error.mockRestore();
  });

  it('"Done" accepts: the action stays, marked done, with its button and without Done/Dismiss', async () => {
    const wrapper = await mountAction();

    const accept = item(wrapper, 11).find('[data-action-accept]');
    expect(accept.classes()).toContain('min-h-11');
    await accept.trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.acceptAdvice).toHaveBeenCalledWith(11);
    const done = item(wrapper, 11);
    expect(done.attributes('data-action-status')).toBe('accepted');
    expect(done.find('[data-action-done]').text()).toContain(
      `${ACTION_KEY}.DONE_LABEL`
    );
    expect(done.find('[data-panel-action-button]').exists()).toBe(true);
    expect(done.find('[data-action-accept]').exists()).toBe(false);
    expect(done.find('[data-action-dismiss]').exists()).toBe(false);
  });

  it('a failed "Done" warns and keeps the action open', async () => {
    CrmMetaAdsConnectionAPI.acceptAdvice.mockRejectedValue(new Error('422'));
    const wrapper = await mountAction();

    await item(wrapper, 11).find('[data-action-accept]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CRM_KANBAN.META_ADS_HUB.AI.DAILY.DONE_FAILED'
    );
    expect(item(wrapper, 11).attributes('data-action-status')).toBe('open');
    expect(item(wrapper, 11).find('[data-action-accept]').exists()).toBe(true);
  });

  it('"Dismiss" removes the action and asks the panel for the next one', async () => {
    const wrapper = await mountAction();

    await item(wrapper, 12).find('[data-action-dismiss]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.dismissAdvice).toHaveBeenCalledWith(12);
    expect(item(wrapper, 12).exists()).toBe(false);
    expect(wrapper.findAll('[data-panel-action]')).toHaveLength(2);
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('a failed "Dismiss" warns and keeps the action', async () => {
    CrmMetaAdsConnectionAPI.dismissAdvice.mockRejectedValue(new Error('500'));
    const wrapper = await mountAction();

    await item(wrapper, 12).find('[data-action-dismiss]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CRM_KANBAN.META_ADS_HUB.AI.DAILY.DISMISS_FAILED'
    );
    expect(item(wrapper, 12).exists()).toBe(true);
    expect(wrapper.emitted('changed')).toBeUndefined();
  });

  it('scale opens Meta Ads Manager in a new tab and records the opening', async () => {
    const wrapper = await mountAction({ advice: advice([SCALE]) });

    const link = item(wrapper, 21).find('[data-panel-action-button]');
    expect(link.element.tagName).toBe('A');
    expect(link.attributes('href')).toBe(SCALE.button.url);
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.classes()).toContain('min-h-11');
    await link.trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.openAdvice).toHaveBeenCalledWith(21);
    expect(wrapper.emitted('act')).toBeUndefined();
  });

  it('auction pressure: "Got it" is the acceptance, with Dismiss and no separate Done', async () => {
    const wrapper = await mountAction({ advice: advice([STALLED, AUCTION]) });

    const auction = item(wrapper, 31);
    expect(auction.find('[data-action-accept]').exists()).toBe(false);
    expect(auction.find('[data-action-dismiss]').exists()).toBe(true);
    const gotIt = auction.find('[data-panel-action-button]');
    expect(gotIt.text()).toContain(`${ACTION_KEY}.AUCTION_PRESSURE.BUTTON`);
    await gotIt.trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.acceptAdvice).toHaveBeenCalledWith(31);
    expect(CrmMetaAdsConnectionAPI.openAdvice).not.toHaveBeenCalled();
    expect(wrapper.emitted('act')).toBeUndefined();
    expect(item(wrapper, 31).attributes('data-action-status')).toBe('accepted');
    expect(item(wrapper, 31).find('[data-panel-action-button]').exists()).toBe(
      false
    );
  });

  it('wait, on track and no data have no button and no Done/Dismiss', async () => {
    const wrapper = await mountAction({ advice: advice([ON_TRACK]) });

    const filler = wrapper.find('[data-panel-action]');
    expect(filler.attributes('data-action-kind')).toBe('on_track');
    expect(filler.find('[data-panel-action-button]').exists()).toBe(false);
    expect(filler.find('[data-action-accept]').exists()).toBe(false);
    expect(filler.find('[data-action-dismiss]').exists()).toBe(false);
  });

  it('asks the AI only while pending, shows "writing" and takes the answer of the same run', async () => {
    let answer;
    CrmMetaAdsConnectionAPI.dailyAction.mockReturnValue(
      new Promise(resolve => {
        answer = resolve;
      })
    );
    const wrapper = await mountAction({
      advice: advice([STALLED], { status: 'pending', reason: null }),
      days: 7,
    });

    expect(CrmMetaAdsConnectionAPI.dailyAction).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-daily-writing]').exists()).toBe(true);

    answer({
      data: {
        daily_action: advice(
          [{ ...STALLED, source: 'ai', headline: 'Retome as propostas.' }],
          { status: 'written', reason: null }
        ),
      },
    });
    await flushPromises();

    expect(wrapper.find('[data-daily-text]').text()).toBe(
      'Retome as propostas.'
    );
    expect(wrapper.find('[data-daily-ai-badge]').exists()).toBe(true);
    expect(wrapper.find('[data-daily-writing]').exists()).toBe(false);
  });

  it('drops an AI answer of another run', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: {
        daily_action: {
          ...advice([{ ...STALLED, source: 'ai', headline: 'Outro run' }]),
          run_id: 999,
        },
      },
    });
    const wrapper = await mountAction({
      advice: advice([STALLED], { status: 'pending', reason: null }),
    });

    expect(wrapper.find('[data-daily-text]').text()).toBe(
      `${ACTION_KEY}.STALLED_QUOTES.TEXT`
    );
  });

  it('a failed AI request keeps the rule with a notice', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockRejectedValue(new Error('x'));
    const wrapper = await mountAction({
      advice: advice([STALLED], { status: 'pending', reason: null }),
    });

    expect(wrapper.find('[data-daily-text]').text()).toBe(
      `${ACTION_KEY}.STALLED_QUOTES.TEXT`
    );
    expect(wrapper.find('[data-daily-notice]').text()).toContain(
      'AI.DAILY.FAILED'
    );
  });

  it('says so when the AI did not answer, and stays silent for other reasons', async () => {
    const aiError = await mountAction({
      advice: advice([STALLED], { status: 'rule', reason: 'ai_error' }),
    });
    expect(aiError.find('[data-daily-notice]').text()).toContain(
      'AI.DAILY.AI_ERROR'
    );
    aiError.unmount();

    const unavailable = await mountAction({
      advice: advice([STALLED], { status: 'rule', reason: 'ai_unavailable' }),
    });
    expect(unavailable.find('[data-daily-notice]').exists()).toBe(false);
    expect(CrmMetaAdsConnectionAPI.dailyAction).not.toHaveBeenCalled();
  });

  it('tells the screen reader whether the list of the button is open', async () => {
    const wrapper = await mountAction({ expanded: ['stalled_list'] });

    expect(
      item(wrapper, 11)
        .find('[data-panel-action-button]')
        .attributes('aria-expanded')
    ).toBe('true');
    expect(
      item(wrapper, 12)
        .find('[data-panel-action-button]')
        .attributes('aria-expanded')
    ).toBe('false');
    expect(
      item(wrapper, 13)
        .find('[data-panel-action-button]')
        .attributes('aria-expanded')
    ).toBeUndefined();
  });
});
