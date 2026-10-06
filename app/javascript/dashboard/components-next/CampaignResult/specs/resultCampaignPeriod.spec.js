import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';
import enProtection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';

// #990: "Envio pausado" showed the account's 7-day protection window (all zeros for a campaign
// paused weeks ago) right under the campaign totals. Now it says why it paused and shows THIS
// campaign's numbers by period, the account window staying under "Ver detalhes".
const api = vi.hoisted(() => ({ getPeriodMetrics: vi.fn() }));
vi.mock('dashboard/api/campaignResults', () => ({ default: api }));

const { default: ResultProtectionCard } = await import(
  '../ResultProtectionCard.vue'
);

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const HEALTH = enResult.RESULT_JOURNEY.EMAIL_HEALTH;
const PERIOD = HEALTH.PERIOD;
const PROTECTION = enProtection.EMAIL_CAMPAIGN_PROTECTION;

const mountCard = campaign =>
  mount(ResultProtectionCard, {
    props: { campaign },
    attachTo: document.body,
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentUser: () => ({ accounts: [{ id: 1, permissions: [] }] }),
            getCurrentCustomRoleId: () => null,
            getCurrentAccountId: () => 1,
          },
        }),
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...enResult, ...enProtection } },
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
    },
  });

const pausedCampaign = {
  id: 9,
  status: 'paused',
  pause_reason: 'hard_bounce_rate',
  protection: {
    state: 'healthy',
    release_eligible: true,
    provider: { state: 'healthy' },
    capabilities: { resume: true, reevaluate: true },
    current: {
      sent: 0,
      permanent_bounces: 0,
      temporary_bounces: 0,
      complaints: 0,
      evaluated_at: '2026-10-06T12:00:00Z',
      window_start: '2026-09-29T12:00:00Z',
      window_end: '2026-10-06T12:00:00Z',
    },
  },
};

const ALL = {
  period: 'all',
  sent: 1804,
  permanent_bounces: 124,
  temporary_bounces: 9,
  complaints: 2,
  hard_bounce_rate: 6.87,
  complaint_rate: 0.11,
};
const EMPTY = {
  period: '7',
  sent: 0,
  permanent_bounces: 0,
  temporary_bounces: 0,
  complaints: 0,
  hard_bounce_rate: null,
  complaint_rate: null,
};

beforeEach(() => {
  vi.clearAllMocks();
  api.getPeriodMetrics.mockImplementation((_channel, _id, period) =>
    Promise.resolve({ data: { payload: period === 'all' ? ALL : EMPTY } })
  );
});

describe('"Como foi esta campanha" (#990)', () => {
  it('opens on "Desde o início" with the numbers of this campaign and rates over sent', async () => {
    const wrapper = mountCard(pausedCampaign);
    await flushPromises();

    expect(api.getPeriodMetrics).toHaveBeenCalledWith(
      'email',
      9,
      'all',
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    const section = wrapper.find('[data-campaign-period]');
    expect(section.find('h3').text()).toBe(PERIOD.TITLE);
    const buttons = section.findAll('[data-period]');
    expect(buttons.map(button => button.text())).toEqual([
      PERIOD.OPTIONS['7'],
      PERIOD.OPTIONS['14'],
      PERIOD.OPTIONS['30'],
      PERIOD.OPTIONS.ALL,
    ]);
    expect(buttons.map(button => button.attributes('aria-pressed'))).toEqual([
      'false',
      'false',
      'false',
      'true',
    ]);
    expect(buttons.every(button => button.element.tagName === 'BUTTON')).toBe(
      true
    );
    expect(wrapper.find('select').exists()).toBe(false);
    expect(
      section
        .findAll('[data-metric]')
        .map(item => item.attributes('data-metric'))
    ).toEqual(['sent', 'permanent', 'temporary', 'complained']);
    expect(section.find('[data-metric="sent"]').text()).toContain('1,804');
    expect(section.find('[data-metric="permanent"]').text()).toContain('124');
    expect(section.find('[data-metric="permanent"]').text()).toContain(
      '6.87% of sent'
    );
    expect(section.find('[data-metric="complained"]').text()).toContain(
      '0.11% of sent'
    );
    wrapper.unmount();
  });

  it('switches period and says so in one sentence when the campaign sent nothing', async () => {
    const wrapper = mountCard(pausedCampaign);
    await flushPromises();

    await wrapper.find('[data-period="7"]').trigger('click');
    await flushPromises();

    expect(api.getPeriodMetrics).toHaveBeenLastCalledWith(
      'email',
      9,
      '7',
      expect.anything()
    );
    expect(wrapper.find('[data-period="7"]').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(wrapper.find('[data-period-empty]').text()).toBe(PERIOD.EMPTY);
    expect(wrapper.find('[data-period-metrics]').exists()).toBe(false);

    await wrapper.find('[data-period="all"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-period-empty]').exists()).toBe(false);
    expect(wrapper.find('[data-metric="sent"]').text()).toContain('1,804');
    wrapper.unmount();
  });

  it('tells an error apart from an empty period', async () => {
    api.getPeriodMetrics.mockRejectedValueOnce(new Error('network'));
    const wrapper = mountCard(pausedCampaign);
    await flushPromises();

    expect(wrapper.find('[data-period-error]').text()).toBe(PERIOD.ERROR);
    expect(wrapper.find('[data-period-empty]').exists()).toBe(false);
    wrapper.unmount();
  });
});

describe('"Por que pausou" (#990)', () => {
  it('says the recorded reason and what the protection looks at, keeping every action', async () => {
    const wrapper = mountCard(pausedCampaign);
    await flushPromises();

    const why = wrapper.find('[data-protection-why]');
    expect(why.text()).toContain(HEALTH.WHY.LABEL);
    expect(why.text()).toContain(HEALTH.WHY.hard_bounce_rate);
    expect(why.find('[data-protection-why-scope]').text()).toBe(
      HEALTH.WHY.SCOPE
    );
    expect(
      wrapper
        .findAll('[data-protection-action]')
        .map(button => button.attributes('data-protection-action'))
    ).toEqual(['resume', 'reevaluate', 'problems']);

    await wrapper.find('[data-protection-details-toggle]').trigger('click');
    const current = wrapper.find('[data-section="CURRENT"]');
    expect(current.find('h3').text()).toBe(HEALTH.ACCOUNT_WINDOW);
    expect(current.text()).toContain(PROTECTION.WINDOW.split(':')[0]);
    wrapper.unmount();
  });

  it('reuses the protection text for other reasons and skips the 7-day note on a manual pause', async () => {
    const wrapper = mountCard({ ...pausedCampaign, pause_reason: 'manual' });
    await flushPromises();

    const why = wrapper.find('[data-protection-why]');
    expect(why.text()).toContain(PROTECTION.REASON.manual);
    expect(why.find('[data-protection-why-scope]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('says the reason once, the header adding only a different block of now', async () => {
    const wrapper = mountCard(pausedCampaign);
    await flushPromises();
    expect(wrapper.find('[data-protection-reason]').exists()).toBe(false);
    wrapper.unmount();

    const blocked = mountCard({
      ...pausedCampaign,
      pause_reason: 'manual',
      protection: {
        ...pausedCampaign.protection,
        provider: { state: 'blocked' },
      },
    });
    await flushPromises();
    expect(blocked.find('[data-protection-reason]').text()).toBe(
      PROTECTION.REASON.provider
    );
    expect(blocked.find('[data-protection-why]').text()).toContain(
      PROTECTION.REASON.manual
    );
    blocked.unmount();
  });

  it('has no "Por que pausou" while the campaign is not paused', async () => {
    const wrapper = mountCard({
      ...pausedCampaign,
      status: 'sending',
      pause_reason: null,
    });
    await flushPromises();

    expect(wrapper.find('[data-protection-why]').exists()).toBe(false);
    expect(wrapper.find('[data-campaign-period]').exists()).toBe(true);
    wrapper.unmount();
  });
});
