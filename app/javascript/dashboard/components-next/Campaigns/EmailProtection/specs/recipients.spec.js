import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import enProtection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import ptProtection from 'dashboard/i18n/locale/pt_BR/emailCampaignProtection.json';
import enCrm from 'dashboard/i18n/locale/en/crm.json';
import ptCrm from 'dashboard/i18n/locale/pt_BR/crm.json';
import arProtection from 'dashboard/i18n/locale/ar/emailCampaignProtection.json';
import arCrm from 'dashboard/i18n/locale/ar/crm.json';
import Reports from 'dashboard/api/emailCampaignReports';
import Recipients from '../EmailRecipients.vue';
vi.mock('dashboard/api/emailCampaignReports', () => ({
  default: { getRecipients: vi.fn(), export: vi.fn() },
}));
const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});
const response = {
  data: {
    payload: {
      recipients: [
        {
          id: 1,
          email: 'synthetic@example.test',
          name: 'Synthetic',
          status: 'delivered',
          attempts: 0,
        },
      ],
      meta: { count: 100, per_page: 50, current_page: 1, total_pages: 2 },
    },
  },
};

describe.each(['en', 'pt_BR'])('recipient server filters (%s)', locale => {
  let wrapper;
  let t;
  beforeEach(() => {
    Reports.getRecipients.mockResolvedValue(response);
    const i18n = createI18n({
      legacy: false,
      locale,
      messages: {
        en: { ...enCrm, ...enProtection },
        pt_BR: { ...ptCrm, ...ptProtection },
      },
    });
    t = i18n.global.t;
    wrapper = mount(Recipients, {
      props: { campaignId: 7 },
      global: { plugins: [i18n] },
    });
  });
  afterEach(() => {
    wrapper.unmount();
    vi.useRealTimers();
  });
  it.each([
    ['direct_inbox', undefined, 'accepted_service', 'accepted_service'],
    ['ses', undefined, 'delivered', 'delivered'],
    [undefined, undefined, 'acceptance_recorded', 'acceptance_recorded'],
    ['ses', 'direct_inbox', 'accepted_service', 'delivered'],
    ['direct_inbox', 'ses', 'delivered', 'accepted_service'],
    ['ses', null, 'acceptance_recorded', 'delivered'],
  ])(
    'uses row/meta scope (%s, %s) and keeps filter/export values',
    async (metaMode, rowMode, badge, filter) => {
      await flushPromises();
      const next = structuredClone(response);
      next.data.payload.meta.delivery_mode = metaMode;
      if (rowMode !== undefined)
        next.data.payload.recipients[0].delivery_mode = rowMode;
      Reports.getRecipients.mockResolvedValue(next);
      await wrapper.setProps({ refreshKey: 1 });
      await flushPromises();
      expect(wrapper.findAll('tbody td')[2].text()).toBe(
        t(`EMAIL_CAMPAIGN_PROTECTION.STATUS.${badge}`)
      );
      expect(wrapper.find('option[value="delivered"]').text()).toBe(
        t(`EMAIL_CAMPAIGN_PROTECTION.STATUS.${filter}`)
      );
      await wrapper.find('select').setValue('delivered');
      await flushPromises();
      expect(Reports.getRecipients).toHaveBeenLastCalledWith(
        7,
        expect.objectContaining({ status: 'delivered', page: 1 })
      );
      Reports.export.mockRejectedValue(new Error('synthetic export failure'));
      await wrapper
        .findAll('button')
        .find(button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.EXPORT'))
        .trigger('click');
      await flushPromises();
      expect(Reports.export).toHaveBeenLastCalledWith(7, {
        search: '',
        status: 'delivered',
        problem: false,
      });
      expect(wrapper.text()).toContain(
        t('EMAIL_CAMPAIGN_PROTECTION.METRICS_HINT')
      );
    }
  );
  it('clears previous campaign provenance while the new recipients are pending', async () => {
    await flushPromises();
    const next = structuredClone(response);
    next.data.payload.meta.delivery_mode = 'direct_inbox';
    Reports.getRecipients.mockResolvedValueOnce(next);
    await wrapper.setProps({ refreshKey: 1 });
    await flushPromises();
    let resolve;
    Reports.getRecipients.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await wrapper.setProps({ campaignId: 8 });
    expect(wrapper.find('option[value="delivered"]').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.acceptance_recorded')
    );
    resolve(response);
    await flushPromises();
    expect(wrapper.findAll('tbody td')[2].text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.acceptance_recorded')
    );
  });
  it('combines search, status, problem and pagination; clears filters server-side', async () => {
    await flushPromises();
    await wrapper.find('input[type="text"]').setValue('ana');
    await wrapper.find('select').setValue('bounced');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await flushPromises();
    expect(Reports.getRecipients).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({
        page: 1,
        search: 'ana',
        status: 'bounced',
        problem: true,
      })
    );
    await wrapper
      .findAll('button')
      .find(
        button => button.text() === t('CAMPAIGN_MANAGEMENT.RECIPIENTS.NEXT')
      )
      .trigger('click');
    await flushPromises();
    expect(Reports.getRecipients).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({
        page: 2,
        search: 'ana',
        status: 'bounced',
        problem: true,
      })
    );
    await wrapper.find('select').setValue('delivered');
    await flushPromises();
    expect(Reports.getRecipients).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({ page: 1, status: 'delivered' })
    );
    await wrapper
      .findAll('button')
      .find(button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.CLEAR'))
      .trigger('click');
    await flushPromises();
    expect(Reports.getRecipients).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({
        page: 1,
        search: '',
        status: '',
        problem: false,
      })
    );
  });
  it('keeps filters after refresh and exports exactly those filters; shows export errors', async () => {
    await flushPromises();
    await wrapper.find('input[type="text"]').setValue('ana');
    await wrapper.find('select').setValue('attention');
    await flushPromises();
    await wrapper.setProps({ refreshKey: 1 });
    await flushPromises();
    expect(Reports.getRecipients).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({ search: 'ana', status: '', problem: true })
    );
    Reports.export.mockRejectedValue({
      response: { data: { error: 'provider private token' } },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.EXPORT'))
      .trigger('click');
    await flushPromises();
    expect(Reports.export).toHaveBeenCalledWith(7, {
      search: 'ana',
      status: '',
      problem: true,
    });
    expect(wrapper.find('[role="alert"]').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.ERROR')
    );
    expect(wrapper.text()).not.toContain('private token');
  });
  it('rejects out-of-order data even when the mock transport ignores abort', async () => {
    await flushPromises();
    let resolveOld;
    Reports.getRecipients.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    await wrapper.find('select').setValue('sent');
    await wrapper.find('select').setValue('delivered');
    await flushPromises();
    resolveOld({
      data: {
        payload: {
          recipients: [{ id: 2, email: 'old@example.test', status: 'sent' }],
          meta: {},
        },
      },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('synthetic@example.test');
    expect(wrapper.text()).not.toContain('old@example.test');
  });
  it('shows a request error instead of a successful empty list', async () => {
    await flushPromises();
    Reports.getRecipients.mockRejectedValue(new Error('private'));
    await wrapper.find('select').setValue('failed');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.ERROR')
    );
    expect(wrapper.text()).not.toContain(t('EMAIL_CAMPAIGN_PROTECTION.EMPTY'));
  });
  it('labels local preflight exclusions separately from tenant protection', async () => {
    await flushPromises();
    const next = structuredClone(response);
    next.data.payload.recipients = [
      {
        id: 10,
        email: 'invalid@example.test',
        status: 'suppressed',
        preflight_status: 'invalid',
        suppression_reason: null,
      },
      {
        id: 11,
        email: 'review@example.test',
        status: 'suppressed',
        preflight_status: 'review',
        suppression_reason: null,
      },
      {
        id: 12,
        email: 'protected@example.test',
        status: 'suppressed',
        preflight_status: 'invalid',
        suppression_reason: 'hard_bounce',
      },
    ];
    next.data.payload.meta.count = 3;
    next.data.payload.meta.total_pages = 1;
    Reports.getRecipients.mockResolvedValue(next);
    await wrapper.setProps({ refreshKey: 71 });
    await flushPromises();
    const labels = wrapper
      .findAll('tbody tr')
      .map(row => row.findAll('td')[2].text());
    expect(labels).toEqual([
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.invalid'),
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.review'),
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.suppressed'),
    ]);
  });

  it('keeps retry counters in optional details and renders full email as text', async () => {
    await flushPromises();
    expect(wrapper.find('thead').text()).not.toContain(
      t('CAMPAIGN_MANAGEMENT.TABLE.ATTEMPTS')
    );
    expect(wrapper.find('details').text()).toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.RETRY_COUNT', { count: '0' })
    );
    expect(wrapper.find('td').text()).toBe('synthetic@example.test');
  });
  it('refreshes idle recipients while visible with bounded backoff until unmount', async () => {
    await flushPromises();
    wrapper.unmount();
    vi.useFakeTimers();
    const visibility = vi
      .spyOn(document, 'visibilityState', 'get')
      .mockReturnValue('hidden');
    const i18n = createI18n({
      legacy: false,
      locale,
      messages: {
        en: { ...enCrm, ...enProtection },
        pt_BR: { ...ptCrm, ...ptProtection },
      },
    });
    wrapper = mount(Recipients, {
      props: { campaignId: 7 },
      global: { plugins: [i18n] },
    });
    await flushPromises();
    Reports.getRecipients.mockClear();
    await vi.advanceTimersByTimeAsync(2 * 60000);
    expect(Reports.getRecipients).not.toHaveBeenCalled();
    visibility.mockReturnValue('visible');
    await vi.advanceTimersByTimeAsync(12 * 60000);
    expect(Reports.getRecipients).toHaveBeenCalledTimes(4);
    await vi.advanceTimersByTimeAsync(50 * 60000);
    expect(Reports.getRecipients).toHaveBeenCalledTimes(14);
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(10 * 60000);
    expect(Reports.getRecipients).toHaveBeenCalledTimes(14);
  });
});

describe('recipient RTL and full identity semantics', () => {
  it('isolates only email fields and preserves the full international name in details', async () => {
    const recipient = {
      id: 9,
      email: `${'long-address-'.repeat(10)}@example.org`,
      name: 'مريم 山田 Zoë García '.repeat(15),
      status: 'delivered',
      delivery_mode: 'ses',
    };
    Reports.getRecipients.mockResolvedValue({
      data: { payload: { recipients: [recipient], meta: {} } },
    });
    const i18n = createI18n({
      legacy: false,
      locale: 'ar',
      fallbackLocale: false,
      messages: { ar: { ...arCrm, ...arProtection } },
    });
    const wrapper = mount(Recipients, {
      props: { campaignId: 7 },
      attrs: { dir: 'rtl' },
      global: { plugins: [i18n] },
    });
    await flushPromises();
    const row = wrapper.find('tbody tr');
    expect(row.findAll('bdi[dir="ltr"]')).toHaveLength(2);
    expect(row.find('td bdi').text()).toBe(recipient.email);
    expect(row.find('details bdi').text()).toBe(recipient.email);
    expect(
      row.findAll('td').every(cell => cell.attributes('dir') === undefined)
    ).toBe(true);
    expect(row.findAll('td')[2].text()).toBe(
      i18n.global.t('EMAIL_CAMPAIGN_PROTECTION.STATUS.delivered')
    );
    expect(row.find('details').text()).toContain(recipient.name.trim());
    expect(row.find('summary').attributes('tabindex')).not.toBe('-1');
    const writeText = vi.fn().mockResolvedValue();
    vi.stubGlobal('navigator', { clipboard: { writeText } });
    await row.find('details button').trigger('click');
    await flushPromises();
    expect(writeText).toHaveBeenCalledWith(recipient.email);
    wrapper.unmount();
    vi.unstubAllGlobals();
  });
});
