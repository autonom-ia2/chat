import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsDailyAction from '../components/MetaAdsDailyAction.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { dailyAction: vi.fn() },
}));

const ACTION = {
  kind: 'stalled_quotes',
  count: 4,
  value: 6200,
  days: 3,
  ad_name: 'Promo outubro',
  cards: [],
};
const RULE_TEXT = { text: 'Texto da regra', why: 'Porquê da regra' };
const AI = {
  source: 'ai',
  reason: null,
  kind: 'stalled_quotes',
  ad_id: null,
  headline: 'Retome as 4 propostas paradas hoje.',
  body: 'Uma mensagem curta para cada cliente basta.',
  why: 'Somam R$ 6.200,00 parados há mais de 3 dias.',
  days: 7,
  generated_at: '2026-10-06T18:00:00Z',
};

const mountAction = async (props = {}) => {
  const wrapper = mount(MetaAdsDailyAction, {
    props: { action: ACTION, ruleText: RULE_TEXT, days: 7, ...props },
    global: {
      mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('Anúncios da Meta · o que fazer hoje pela IA (#1100, F4a)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows the rule at once and swaps in the AI text with its why', async () => {
    let answer;
    CrmMetaAdsConnectionAPI.dailyAction.mockReturnValue(
      new Promise(resolve => {
        answer = resolve;
      })
    );
    const wrapper = mount(MetaAdsDailyAction, {
      props: { action: ACTION, ruleText: RULE_TEXT, days: 7 },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();

    expect(wrapper.find('[data-daily-text]').text()).toBe('Texto da regra');
    expect(wrapper.find('[data-daily-writing]').exists()).toBe(true);

    answer({ data: { daily_action: AI } });
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.dailyAction).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-daily-text]').text()).toBe(AI.headline);
    expect(wrapper.find('[data-daily-body]').text()).toBe(AI.body);
    expect(wrapper.find('[data-daily-why]').text()).toContain(AI.why);
    expect(wrapper.find('[data-daily-why-label]').text()).toBe(
      'CRM_KANBAN.META_ADS_HUB.AI.DAILY.WHY_LABEL'
    );
    expect(wrapper.find('[data-daily-ai-badge]').exists()).toBe(true);
    expect(
      wrapper.find('[data-panel-action]').attributes('data-action-source')
    ).toBe('ai');
    expect(wrapper.find('[data-daily-notice]').exists()).toBe(false);
  });

  it('keeps the rule in silence when there is no AI for the account', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: {
        daily_action: { ...AI, source: 'rule', reason: 'ai_unavailable' },
      },
    });
    const wrapper = await mountAction();

    expect(wrapper.find('[data-daily-text]').text()).toBe('Texto da regra');
    expect(wrapper.find('[data-daily-why]').text()).toBe('Porquê da regra');
    expect(wrapper.find('[data-daily-ai-badge]').exists()).toBe(false);
    expect(wrapper.find('[data-daily-notice]').exists()).toBe(false);
  });

  it('says so when the AI did not answer, and keeps the rule', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: { daily_action: { ...AI, source: 'rule', reason: 'ai_error' } },
    });
    const wrapper = await mountAction();

    expect(wrapper.find('[data-daily-text]').text()).toBe('Texto da regra');
    expect(wrapper.find('[data-daily-notice]').text()).toContain(
      'AI.DAILY.AI_ERROR'
    );
  });

  it('a failed request also falls back to the rule with a notice', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockRejectedValue(
      new Error('ai_request_failed')
    );
    const wrapper = await mountAction();

    expect(wrapper.find('[data-daily-text]').text()).toBe('Texto da regra');
    expect(wrapper.find('[data-daily-notice]').text()).toContain(
      'AI.DAILY.FAILED'
    );
  });

  it('the button tells the panel what to do', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: { daily_action: { ...AI, kind: 'review_ad', ad_id: '456' } },
    });
    const wrapper = await mountAction();

    const button = wrapper.find('[data-panel-action-button]');
    expect(button.classes()).toContain('min-h-11');
    expect(button.text()).toContain('AI.DAILY.REVIEW_AD_BUTTON');
    await button.trigger('click');

    expect(wrapper.emitted('act')).toEqual([
      [{ kind: 'review_ad', adId: '456' }],
    ]);
  });

  it('wait and on track have no button', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: { daily_action: { ...AI, kind: 'on_track' } },
    });
    const wrapper = await mountAction();

    expect(wrapper.find('[data-panel-action-button]').exists()).toBe(false);
  });

  it.each(['wait', 'review_ad'])(
    'keeps the stalled quotes one click away when the AI picks %s',
    async aiKind => {
      CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValueOnce({
        data: { daily_action: { ...AI, kind: aiKind, ad_id: '456' } },
      });
      const wrapper = await mountAction();

      const stalled = wrapper.find('[data-panel-stalled-button]');
      expect(stalled.text()).toContain('PANEL.ACTION.STALLED_QUOTES.BUTTON');
      expect(stalled.classes()).toContain('min-h-11');
      await stalled.trigger('click');
      expect(wrapper.emitted('act')).toEqual([
        [{ kind: 'stalled_quotes', adId: null }],
      ]);
    }
  );

  it('no extra stalled button when the AI keeps the stalled quotes or the rule found none', async () => {
    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: { daily_action: AI },
    });
    expect(
      (await mountAction()).find('[data-panel-stalled-button]').exists()
    ).toBe(false);

    CrmMetaAdsConnectionAPI.dailyAction.mockResolvedValue({
      data: { daily_action: { ...AI, kind: 'wait' } },
    });
    const noStalled = await mountAction({
      action: { kind: 'wait', ad_name: 'Promo', missing_conversations: 3 },
    });
    expect(noStalled.find('[data-panel-stalled-button]').exists()).toBe(false);
  });

  it('asks again for a new period and drops the old answer', async () => {
    let slow;
    CrmMetaAdsConnectionAPI.dailyAction
      .mockReturnValueOnce(
        new Promise(resolve => {
          slow = resolve;
        })
      )
      .mockResolvedValueOnce({
        data: { daily_action: { ...AI, headline: 'Trinta dias', days: 30 } },
      });
    const wrapper = await mountAction();

    await wrapper.setProps({ days: 30 });
    await flushPromises();
    slow({ data: { daily_action: { ...AI, headline: 'Sete dias' } } });
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.dailyAction).toHaveBeenLastCalledWith(30);
    expect(wrapper.find('[data-daily-text]').text()).toBe('Trinta dias');
  });
});
