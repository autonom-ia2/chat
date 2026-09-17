import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/emailCampaignProtection.json';
import API from 'dashboard/api/emailCampaigns';
import Health from '../EmailCampaignHealth.vue';
import Panel from '../EmailProtectionPanel.vue';
vi.mock('dashboard/api/emailCampaigns', () => ({
  default: { reevaluate: vi.fn(), recheck: vi.fn(), resume: vi.fn() },
}));
const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

describe.each(['en', 'pt_BR'])('server protection actions (%s)', locale => {
  let wrapper;
  let t;
  const campaign = {
    id: 1,
    status: 'paused',
    pause_reason: 'reputation',
    protection: {
      state: 'paused',
      capabilities: { reevaluate: true, resume: false },
    },
    preflight: { can_recheck: true },
  };
  beforeEach(() => {
    const i18n = createI18n({ legacy: false, locale, messages: { en, pt_BR } });
    t = i18n.global.t;
    wrapper = mount(Health, {
      props: { campaign },
      global: { plugins: [i18n] },
    });
  });
  afterEach(() => wrapper.unmount());
  it('calls re-evaluate once and reports still paused instead of success', async () => {
    let resolve;
    API.reevaluate.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.REEVALUATE'));
    await button.trigger('click');
    await button.trigger('click');
    expect(API.reevaluate).toHaveBeenCalledTimes(1);
    resolve({ data: { payload: campaign } });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.STILL_BLOCKED')
    );
    expect(
      wrapper
        .findAll('button')
        .some(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'))
    ).toBe(false);
    expect(wrapper.emitted('updated')[0][0].status).toBe('paused');
  });
  it('calls address recheck and uses safe translated machine errors', async () => {
    API.recheck.mockRejectedValue({
      response: {
        data: {
          error_code: 'ses_account_paused',
          message: 'private provider token',
        },
      },
    });
    await wrapper
      .findAll('button')
      .find(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.RECHECK'))
      .trigger('click');
    await flushPromises();
    expect(API.recheck).toHaveBeenCalledWith(1);
    expect(wrapper.find('[role="alert"]').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.REASON.provider')
    );
    expect(wrapper.text()).not.toContain('private provider token');
  });
  it('keeps the sticky pause until resume POST succeeds and prevents duplicate requests', async () => {
    const eligible = {
      ...campaign,
      protection: {
        ...campaign.protection,
        release_eligible: true,
        provider: { state: 'healthy' },
        capabilities: { resume: true },
        trigger: {
          at: '2026-09-10',
          reason_code: 'reputation',
          metrics: { sent: 100 },
        },
      },
    };
    await wrapper.setProps({ campaign: eligible });
    let resolve;
    API.resume.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const trigger = wrapper.find('[data-section="TRIGGER"]').text();
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'));
    await button.trigger('click');
    await button.trigger('click');
    expect(API.resume).toHaveBeenCalledTimes(1);
    expect(API.resume).toHaveBeenCalledWith(1);
    expect(wrapper.findComponent(Panel).props('campaign').status).toBe(
      'paused'
    );
    expect(
      wrapper.findComponent(Panel).props('campaign').protection.state
    ).toBe('paused');
    expect(wrapper.find('[data-section="TRIGGER"]').text()).toBe(trigger);
    expect(wrapper.emitted('updated')).toBeUndefined();
    resolve({
      data: {
        payload: {
          ...eligible,
          status: 'sending',
          protection: {
            ...eligible.protection,
            state: 'healthy',
            current: { evaluated_at: '2026-09-16' },
            capabilities: { resume: false },
          },
        },
      },
    });
    await flushPromises();
    expect(wrapper.findComponent(Panel).props('campaign').status).toBe(
      'sending'
    );
    expect(wrapper.emitted('updated')[0][0].status).toBe('sending');
    expect(wrapper.find('[data-section="TRIGGER"]').text()).toBe(trigger);
    expect(
      wrapper
        .findAll('button')
        .some(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'))
    ).toBe(false);
  });
  it.each(['provider_blocked', 'private unknown exception'])(
    'keeps pause and trigger on resume error %s without exposing server details',
    async code => {
      const eligible = {
        ...campaign,
        protection: {
          ...campaign.protection,
          release_eligible: true,
          provider: { state: 'healthy' },
          capabilities: { resume: true },
          trigger: {
            at: '2026-09-10',
            reason_code: 'reputation',
            metrics: { sent: 100 },
          },
        },
      };
      await wrapper.setProps({ campaign: eligible });
      API.resume.mockRejectedValue({
        response: {
          data: { error_code: code, message: 'private provider token' },
        },
      });
      const trigger = wrapper.find('[data-section="TRIGGER"]').text();
      await wrapper
        .findAll('button')
        .find(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'))
        .trigger('click');
      await flushPromises();
      expect(wrapper.findComponent(Panel).props('campaign')).toEqual(eligible);
      expect(wrapper.find('[data-section="TRIGGER"]').text()).toBe(trigger);
      expect(wrapper.find('[role="alert"]').text()).toBe(
        t(
          code === 'provider_blocked'
            ? 'EMAIL_CAMPAIGN_PROTECTION.REASON.provider'
            : 'EMAIL_CAMPAIGN_PROTECTION.ERROR'
        )
      );
      expect(wrapper.text()).not.toContain('private');
      expect(wrapper.emitted('updated')).toBeUndefined();
    }
  );
  it('keeps a successful HTTP response paused when the server denies release', async () => {
    const eligible = {
      ...campaign,
      protection: {
        ...campaign.protection,
        release_eligible: true,
        provider: { state: 'unknown' },
        capabilities: { resume: true },
      },
    };
    await wrapper.setProps({ campaign: eligible });
    API.resume.mockResolvedValue({ data: { payload: campaign } });
    await wrapper
      .findAll('button')
      .find(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'))
      .trigger('click');
    await flushPromises();
    expect(wrapper.findComponent(Panel).props('campaign').status).toBe(
      'paused'
    );
    expect(wrapper.find('[role="alert"]').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.STILL_BLOCKED')
    );
    expect(
      wrapper
        .findAll('button')
        .some(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.RESUME'))
    ).toBe(false);
  });
  it.each(['blocked', 'paused', 'disabled'])(
    'refuses a programmatic resume event when provider is %s',
    async state => {
      await wrapper.setProps({
        campaign: {
          ...campaign,
          protection: {
            state: 'healthy',
            release_eligible: true,
            provider: { state },
            capabilities: { resume: true, override: true },
          },
        },
      });
      wrapper.findComponent(Panel).vm.$emit('resume');
      await flushPromises();
      expect(API.resume).not.toHaveBeenCalled();
      expect(wrapper.emitted('updated')).toBeUndefined();
    }
  );
  it('does not let an action for the previous campaign overwrite the selection', async () => {
    let resolve;
    API.reevaluate.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await wrapper
      .findAll('button')
      .find(item => item.text() === t('EMAIL_CAMPAIGN_PROTECTION.REEVALUATE'))
      .trigger('click');
    await wrapper.setProps({ campaign: { id: 2, status: 'draft' } });
    resolve({ data: { payload: campaign } });
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
  });
});
