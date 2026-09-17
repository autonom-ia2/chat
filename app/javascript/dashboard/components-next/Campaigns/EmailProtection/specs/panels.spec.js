import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/emailCampaignProtection.json';
import Panel from '../EmailProtectionPanel.vue';
import Hygiene from '../EmailHygieneSummary.vue';
import Badge from '../EmailStatusBadge.vue';

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const messages = { en, pt_BR };

describe.each(['en', 'pt_BR'])('protection panels in %s', locale => {
  const i18n = createI18n({ legacy: false, locale, messages });
  const { t } = i18n.global;
  const options = { global: { plugins: [i18n] } };
  it('treats missing protection as unknown, without unsafe resume', () => {
    const wrapper = mount(Panel, {
      ...options,
      props: { campaign: { id: 1, status: 'paused' } },
    });
    expect(wrapper.text()).toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.unknown')
    );
    expect(wrapper.text()).not.toContain(t('EMAIL_CAMPAIGN_PROTECTION.RESUME'));
    expect(wrapper.text()).toContain(t('EMAIL_CAMPAIGN_PROTECTION.SCOPE'));
  });
  it.each([
    [
      'manual',
      { status: 'paused', pause_reason: 'manual' },
      null,
      'STATUS.manual',
    ],
    [
      'manual with account attention',
      { status: 'paused', pause_reason: 'manual' },
      { state: 'attention', reason_code: 'manual' },
      'STATUS.manual',
    ],
    [
      'healthy',
      { status: 'sent' },
      { state: 'healthy', current: { evaluated_at: '2026-09-16' } },
      'HEALTH',
    ],
    ['unknown', { status: 'paused' }, null, 'HEALTH'],
    ['unfresh', { status: 'sent' }, { state: 'healthy' }, 'HEALTH'],
    [
      'reputation',
      { status: 'paused', pause_reason: 'reputation' },
      { state: 'paused' },
      'TITLE',
    ],
    [
      'manual with account pause',
      { status: 'paused', pause_reason: 'manual' },
      {
        state: 'paused',
        reason_code: 'reputation',
        capabilities: { resume: true },
      },
      'TITLE',
    ],
    [
      'manual with provider block',
      { status: 'paused', pause_reason: 'manual' },
      {
        state: 'healthy',
        current: { evaluated_at: '2026-09-16' },
        provider: { state: 'blocked' },
        capabilities: { resume: true },
      },
      'TITLE',
    ],
  ])('uses a truthful title for %s', (_name, campaign, protection, title) => {
    const wrapper = mount(Panel, {
      ...options,
      props: { campaign: { id: 1, ...campaign }, protection },
    });
    expect(wrapper.find('h3').text()).toBe(
      t(`EMAIL_CAMPAIGN_PROTECTION.${title}`)
    );
  });
  it('shows an identical semantic pause badge only once', () => {
    const wrapper = mount(Panel, {
      ...options,
      props: {
        campaign: { id: 1, status: 'paused', pause_reason: 'reputation' },
        protection: { state: 'paused', reason_code: 'reputation' },
      },
    });
    expect(wrapper.findAllComponents(Badge)).toHaveLength(1);
  });
  it('labels distinct account and campaign states using translated context', () => {
    const wrapper = mount(Panel, {
      ...options,
      props: {
        campaign: { id: 1, status: 'paused', pause_reason: 'manual' },
        protection: { state: 'attention', reason_code: 'manual' },
      },
    });
    const badges = wrapper.findAllComponents(Badge);
    expect(badges).toHaveLength(2);
    expect(badges[0].element.parentElement.textContent).toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.HEALTH')
    );
    expect(badges[1].element.parentElement.textContent).toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.CAMPAIGN_STATUS')
    );
  });
  it.each([
    {
      state: 'paused',
      reason_code: 'reputation',
      capabilities: { resume: true },
    },
    { state: 'paused', reason_code: 'manual', capabilities: { resume: true } },
    {
      state: 'healthy',
      reason_code: 'manual',
      provider: { state: 'blocked' },
      capabilities: { resume: true },
    },
  ])(
    'prioritizes an account/provider block over manual campaign pause (%j)',
    protection => {
      const wrapper = mount(Panel, {
        ...options,
        props: {
          campaign: { id: 1, status: 'paused', pause_reason: 'manual' },
          protection,
        },
      });
      expect(wrapper.find('h3').text()).toBe(
        t('EMAIL_CAMPAIGN_PROTECTION.TITLE')
      );
      expect(
        wrapper
          .findAll('button')
          .some(
            button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME')
          )
      ).toBe(false);
      expect(wrapper.text()).not.toContain(
        t('EMAIL_CAMPAIGN_PROTECTION.REASON.manual')
      );
    }
  );
  it('offers deliberate release while keeping the paused title, badge and trigger', async () => {
    const protection = {
      state: 'paused',
      reason_code: 'reputation',
      release_eligible: true,
      provider: { state: 'healthy' },
      capabilities: { resume: true },
      trigger: {
        at: '2026-09-10T12:00:00Z',
        reason_code: 'hard_bounce_rate',
        metrics: { sent: 100, permanent_bounces: 10 },
      },
    };
    const wrapper = mount(Panel, {
      ...options,
      props: {
        campaign: { id: 1, status: 'paused', pause_reason: 'reputation' },
        protection,
      },
    });
    const trigger = wrapper.find('[data-section="TRIGGER"]').text();
    expect(wrapper.find('h3').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.TITLE')
    );
    expect(wrapper.findComponent(Badge).props('record').status).toBe('paused');
    await wrapper
      .findAll('button')
      .find(button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'))
      .trigger('click');
    expect(wrapper.emitted('resume')).toHaveLength(1);
    expect(wrapper.findComponent(Badge).props('record').status).toBe('paused');
    expect(wrapper.find('[data-section="TRIGGER"]').text()).toBe(trigger);
    expect(protection.state).toBe('paused');
  });
  it.each(['blocked', 'paused', 'disabled'])(
    'keeps provider %s visually paused and hides release despite explicit proof',
    state => {
      const wrapper = mount(Panel, {
        ...options,
        props: {
          campaign: { id: 1, status: 'paused', pause_reason: 'manual' },
          protection: {
            state: 'healthy',
            release_eligible: true,
            provider: { state },
            capabilities: { resume: true, override: true },
          },
        },
      });
      expect(wrapper.findComponent(Badge).props('record').status).toBe(
        'paused'
      );
      expect(wrapper.text()).toContain(
        t('EMAIL_CAMPAIGN_PROTECTION.REASON.provider')
      );
      expect(
        wrapper
          .findAll('button')
          .some(
            button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME')
          )
      ).toBe(false);
    }
  );
  it('separates current metrics from the immutable trigger, with sent denominators', async () => {
    const wrapper = mount(Panel, {
      ...options,
      props: {
        campaign: { id: 1, status: 'paused' },
        protection: {
          state: 'attention',
          reason_code: 'reputation',
          capabilities: { reevaluate: true, override: true },
          current: {
            sent: 200,
            permanent_bounces: 1,
            hard_bounce_rate: 0.5,
            evaluated_at: '2026-09-15T12:00:00Z',
            window_start: '2026-09-01',
            window_end: '2026-09-15',
          },
          trigger: {
            at: '2026-09-10T12:00:00Z',
            reason_code: 'hard_bounce_rate',
            metrics: { sent: 100, permanent_bounces: 10, hard_bounce_rate: 10 },
          },
        },
      },
    });
    expect(wrapper.find('[data-section="CURRENT"]').text()).toContain('200');
    expect(wrapper.find('[data-section="TRIGGER"]').text()).toContain('100');
    expect(wrapper.text()).toContain(t('EMAIL_CAMPAIGN_PROTECTION.HARD_RATE'));
    expect(wrapper.text()).not.toContain('hard_bounce_rate');
    expect(wrapper.text()).not.toContain(t('EMAIL_CAMPAIGN_PROTECTION.RESUME'));
    await wrapper
      .findAll('button')
      .find(
        button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.REEVALUATE')
      )
      .trigger('click');
    expect(wrapper.emitted('reevaluate')).toHaveLength(1);
  });
  it.each([
    [{ id: 1, status: 'paused', pause_reason: 'manual' }, false],
    [{ id: 1, status: 'paused', pause_reason: 'reputation' }, false],
    [
      {
        id: 1,
        status: 'paused',
        protection: {
          state: 'unknown',
          provider: { state: 'unknown' },
          capabilities: { resume: true },
        },
      },
      true,
    ],
    [
      {
        id: 1,
        status: 'paused',
        pause_reason: 'manual',
        protection: {
          provider: { state: 'blocked' },
          capabilities: { resume: true },
        },
      },
      false,
    ],
  ])('shows resume only when allowed (%j)', (campaign, allowed) => {
    const wrapper = mount(Panel, { ...options, props: { campaign } });
    expect(
      wrapper
        .findAll('button')
        .some(button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'))
    ).toBe(allowed);
  });
  it.each(['shadow', 'warning'])(
    'labels %s as analysis only and reconciles each row once',
    mode => {
      const wrapper = mount(Hygiene, {
        ...options,
        props: {
          preflight: {
            mode,
            status: 'completed',
            counts: {
              total: 10,
              ready: 2,
              protected: 1,
              invalid: 1,
              review: 1,
              unknown: 1,
              unchecked: 2,
              duplicate: 2,
            },
            can_recheck: true,
          },
        },
      });
      expect(wrapper.text()).toContain(
        t('EMAIL_CAMPAIGN_PROTECTION.ANALYSIS_ONLY')
      );
      expect(wrapper.text()).not.toContain(
        t('EMAIL_CAMPAIGN_PROTECTION.ENFORCED')
      );
      expect(wrapper.findAll('dd').map(node => node.text())).toEqual([
        '10',
        '2',
        '1',
        '1',
        '1',
        '1',
        '2',
        '2',
      ]);
    }
  );
  it('does not invent readiness or reconcile overlapping counters', async () => {
    const wrapper = mount(Hygiene, {
      ...options,
      props: {
        preflight: {
          mode: 'enforce',
          status: 'processing',
          counts: { total: 10, ready: 10, review: 5 },
          can_recheck: true,
        },
      },
    });
    expect(wrapper.text()).toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.PENDING_COUNTS')
    );
    expect(wrapper.findAll('dd')).toHaveLength(0);
    expect(wrapper.text()).toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.analysing')
    );
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('recheck')).toHaveLength(1);
  });
});
