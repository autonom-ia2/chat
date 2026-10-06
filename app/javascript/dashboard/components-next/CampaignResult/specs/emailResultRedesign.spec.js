import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';
import enProtection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import enCrm from 'dashboard/i18n/locale/en/crm.json';

// #990: the e-mail Resultado redraws health, clicks and people in the result layout, keeping
// every action and filter of the old Gestão (O1).
const api = vi.hoisted(() => ({
  reports: { getRecipients: vi.fn(), export: vi.fn() },
  campaigns: { reevaluate: vi.fn(), resume: vi.fn(), recheck: vi.fn() },
}));
vi.mock('dashboard/api/emailCampaignReports', () => ({ default: api.reports }));
vi.mock('dashboard/api/emailCampaigns', () => ({ default: api.campaigns }));
vi.mock(
  'dashboard/components-next/Campaigns/EmailProtection/EmailImportIssues.vue',
  () => ({ default: { name: 'EmailImportIssues', render: () => null } })
);

const { linkLabel, PATH_LIMIT } = await import('../linkLabel');
const { default: ResultLinkClicks } = await import('../ResultLinkClicks.vue');
const { default: ResultProtectionCard } = await import(
  '../ResultProtectionCard.vue'
);
const { default: ResultEmailHealth } = await import('../ResultEmailHealth.vue');
const { default: ResultEmailRecipients } = await import(
  '../ResultEmailRecipients.vue'
);

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const plugins = ({ customRole = null } = {}) => [
  createStore({
    getters: {
      getCurrentUser: () => ({
        accounts: [{ id: 1, permissions: customRole || [] }],
      }),
      getCurrentCustomRoleId: () => (customRole ? 7 : null),
      getCurrentAccountId: () => 1,
    },
  }),
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...enResult, ...enProtection, ...enCrm } },
    missingWarn: false,
    fallbackWarn: false,
  }),
];
const mountWith = (component, props, options = {}) =>
  mount(component, {
    props,
    attachTo: document.body,
    global: { plugins: plugins(options) },
  });

// Built so the linter does not read the test data as a script URL.
const SCRIPT_URL = ['javascript', 'alert(1)'].join(':');
const PROTECTION = enProtection.EMAIL_CAMPAIGN_PROTECTION;
const HEALTH = enResult.RESULT_JOURNEY.EMAIL_HEALTH;
const PEOPLE = enResult.RESULT_JOURNEY.EMAIL_PEOPLE;

describe('"Cliques por link" opens each web address in a new tab (#990)', () => {
  it('only http/https become links, labelled by site and the start of the path', () => {
    expect(linkLabel('https://www.hub2you.ai/live?utm=x')).toEqual({
      href: 'https://www.hub2you.ai/live?utm=x',
      label: 'hub2you.ai/live?utm=x',
    });
    expect(linkLabel('http://hub2you.ai/')).toEqual({
      href: 'http://hub2you.ai/',
      label: 'hub2you.ai',
    });
    const long = linkLabel(`https://hub2you.ai/${'a'.repeat(80)}`);
    expect(long.label).toBe(`hub2you.ai/${'a'.repeat(PATH_LIMIT - 1)}…`);
    expect(long.href).toBe(`https://hub2you.ai/${'a'.repeat(80)}`);
    [SCRIPT_URL, 'mailto:ana@alfa.com.br', 'not a url', ''].forEach(value =>
      expect(linkLabel(value).href).toBeNull()
    );
  });

  it('renders the link with target _blank, rel noopener and the full address in title', () => {
    const wrapper = mountWith(ResultLinkClicks, {
      clicks: [
        { url: 'https://hub2you.ai/live', unique_clicks: 52, total_clicks: 61 },
        { url: SCRIPT_URL, unique_clicks: 1, total_clicks: 1 },
      ],
    });

    const links = wrapper.findAll('[data-link]');
    expect(links).toHaveLength(1);
    expect(links[0].attributes()).toMatchObject({
      href: 'https://hub2you.ai/live',
      target: '_blank',
      rel: 'noopener noreferrer',
      title: 'https://hub2you.ai/live',
    });
    expect(links[0].attributes('aria-label')).toContain(
      'https://hub2you.ai/live'
    );
    const rows = wrapper.findAll('[data-link-row]');
    expect(rows[0].find('[data-unique]').text()).toBe('52');
    expect(rows[0].find('[data-total]').text()).toBe('61');
    expect(rows[1].find('a').exists()).toBe(false);
    expect(rows[1].text()).toContain(SCRIPT_URL);
    wrapper.unmount();
  });
});

const pausedCampaign = {
  id: 9,
  status: 'paused',
  protection: {
    state: 'paused',
    reason_code: 'hard_bounce_rate',
    release_eligible: true,
    provider: { state: 'healthy' },
    capabilities: { resume: true, reevaluate: true },
    current: {
      sent: 1804,
      permanent_bounces: 31,
      hard_bounce_rate: 1.72,
      temporary_bounces: 4,
      complaints: 0,
      complaint_rate: 0,
      evaluated_at: '2026-09-15T13:30:00Z',
    },
  },
};

describe('"Envio pausado" in the result layout (#990)', () => {
  it('says why it paused, what to do, and orders Retomar, Reavaliar, Ver lista de problemas', async () => {
    const wrapper = mountWith(ResultProtectionCard, {
      campaign: pausedCampaign,
    });

    expect(wrapper.find('h2').text()).toBe(PROTECTION.STATUS.paused_unknown);
    expect(wrapper.find('[data-protection-pill]').text()).toBe(
      PROTECTION.STATUS.paused
    );
    expect(wrapper.find('[data-protection-reason]').text()).toBe(
      PROTECTION.REASON.reputation
    );
    expect(wrapper.find('[data-protection-next]').text()).toBe(
      HEALTH.NEXT.RESUME
    );
    expect(
      wrapper
        .findAll('[data-protection-action]')
        .map(button => button.attributes('data-protection-action'))
    ).toEqual(['resume', 'reevaluate', 'problems']);
    expect(
      wrapper.findAll('[data-strip]').map(item => item.attributes('data-strip'))
    ).toEqual(['sent', 'permanent', 'temporary', 'complained']);
    expect(wrapper.find('[data-strip="sent"]').text()).toContain('1,804');
    expect(wrapper.find('[data-protection-checked]').exists()).toBe(true);

    await wrapper.find('[data-protection-action="resume"]').trigger('click');
    await wrapper
      .find('[data-protection-action="reevaluate"]')
      .trigger('click');
    await wrapper.find('[data-protection-action="problems"]').trigger('click');
    expect(Object.keys(wrapper.emitted())).toEqual(
      expect.arrayContaining(['resume', 'reevaluate', 'problems'])
    );

    const toggle = wrapper.find('[data-protection-details-toggle]');
    expect(toggle.attributes('aria-expanded')).toBe('false');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    expect(wrapper.find('[data-section="CURRENT"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('a campaign_view seat reads the block but gets no Retomar nor Reavaliar', () => {
    const wrapper = mountWith(
      ResultProtectionCard,
      { campaign: pausedCampaign },
      { customRole: ['campaign_view'] }
    );

    expect(
      wrapper
        .findAll('[data-protection-action]')
        .map(button => button.attributes('data-protection-action'))
    ).toEqual(['problems']);
    expect(wrapper.find('[data-protection-next]').text()).toBe(
      HEALTH.NEXT.PROBLEMS
    );
    wrapper.unmount();
  });

  it('keeps the old resume call and its answer (O1)', async () => {
    api.campaigns.resume.mockResolvedValue({
      data: { payload: { ...pausedCampaign, status: 'sending' } },
    });
    const wrapper = mountWith(ResultEmailHealth, {
      campaign: {
        ...pausedCampaign,
        preflight: {
          status: 'completed',
          counts: { total: 10, ready: 8, invalid: 2 },
          can_recheck: true,
        },
      },
    });

    expect(wrapper.find('[data-hygiene-card]').text()).toContain(
      HEALTH.HYGIENE_TITLE
    );
    expect(
      wrapper.findAll('[data-count]').map(item => item.attributes('data-count'))
    ).toEqual(['total', 'ready', 'invalid']);

    await wrapper.find('[data-protection-action="resume"]').trigger('click');
    await flushPromises();

    expect(api.campaigns.resume).toHaveBeenCalledWith(9);
    expect(wrapper.emitted('updated')[0][0]).toMatchObject({
      status: 'sending',
    });
    wrapper.unmount();
  });
});

const recipients = [
  {
    id: 1,
    name: 'Ana Maria Souza',
    email: 'ana@alfa.com.br',
    status: 'delivered',
    delivery_mode: 'ses',
    opens: 3,
    clicks: 1,
    attempts: 0,
    sent_at: '2026-09-15T13:30:00Z',
    last_event_at: '2026-09-15T14:00:00Z',
    preflight_status: 'valid',
  },
  {
    id: 2,
    name: '',
    email: 'bia@beta.com',
    status: 'bounced',
    delivery_outcome: 'temporary',
    delivery_mode: 'ses',
    opens: 0,
    clicks: 0,
    attempts: 2,
    sent_at: null,
    last_event_at: null,
    preflight_status: 'review',
    reason_code: 'mailbox_full',
  },
];

const mountPeople = () => {
  api.reports.getRecipients.mockResolvedValue({
    data: {
      payload: {
        recipients,
        meta: { delivery_mode: 'ses', total_pages: 3, current_page: 1 },
      },
    },
  });
  return mountWith(ResultEmailRecipients, { campaignId: '9' });
};

describe('Destinatários of the e-mail Resultado (#990)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows each person with a plain status, opens and clicks, without a native <select>', async () => {
    const wrapper = mountPeople();
    await flushPromises();

    expect(wrapper.find('select').exists()).toBe(false);
    const ana = wrapper.find('[data-people-rows] [data-person="1"]');
    expect(ana.text()).toContain('Ana Maria Souza');
    expect(ana.text()).toContain('ana@alfa.com.br');
    expect(ana.find('[data-person-pill]').text()).toBe(PEOPLE.PILL.DELIVERED);
    expect(ana.find('[data-person-pill]').attributes('title')).toBe(
      PROTECTION.STATUS.delivered
    );
    const bia = wrapper.find('[data-people-rows] [data-person="2"]');
    expect(bia.find('[data-person-pill]').text()).toBe(PEOPLE.PILL.TEMPORARY);
    expect(bia.text()).toContain(PEOPLE.NOT_SENT);
    wrapper.unmount();
  });

  it('details open under the row as labelled pairs, in plain words', async () => {
    const wrapper = mountPeople();
    await flushPromises();

    const toggle = wrapper.find(
      '[data-people-rows] [data-person="2"] [data-person-toggle]'
    );
    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(toggle.attributes('aria-label')).toContain('bia@beta.com');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');

    const details = wrapper.find('[data-people-rows] [data-person-details]');
    const pairs = details
      .findAll('dt')
      .map((term, index) => [term.text(), details.findAll('dd')[index].text()]);
    expect(pairs).toEqual([
      [PEOPLE.FULL_STATUS, PROTECTION.STATUS.temporary],
      [PEOPLE.REASON, PROTECTION.REASON.temporary],
      [PEOPLE.SENT_AT, PEOPLE.NOT_SENT],
      [PEOPLE.LAST_ACTIVITY, PEOPLE.NO_ACTIVITY],
      [PEOPLE.ADDRESS_CHECK, PEOPLE.ADDRESS.REVIEW],
      [PEOPLE.RETRIES, '2 times'],
    ]);
    // The raw retry counter of the old table stays out.
    expect(details.text()).not.toContain(
      PROTECTION.RETRY_COUNT.split('{')[0].trim()
    );
    wrapper.unmount();
  });

  it('filters by status with ChoiceSelect, opens the problem filter and keeps export and pages', async () => {
    const wrapper = mountPeople();
    await flushPromises();
    expect(wrapper.find('[data-people-problem]').exists()).toBe(false);

    const [status] = wrapper.findAllComponents({ name: 'ChoiceSelect' });
    status.vm.$emit('update:modelValue', 'attention');
    await flushPromises();
    expect(api.reports.getRecipients).toHaveBeenLastCalledWith(
      '9',
      expect.objectContaining({ status: '', problem: true, page: 1 })
    );
    const problem = wrapper.findAllComponents({ name: 'ChoiceSelect' })[1];
    expect(problem.props('options').map(option => option.value)).toEqual([
      'attention',
      'temporary_bounced',
      'hard_bounced',
      'complained',
      'preflight_invalid',
      'preflight_review',
    ]);
    problem.vm.$emit('update:modelValue', 'complained');
    await flushPromises();
    expect(api.reports.getRecipients).toHaveBeenLastCalledWith(
      '9',
      expect.objectContaining({ status: 'complained', problem: true })
    );

    api.reports.export.mockResolvedValue({ data: new Blob(['csv']) });
    URL.createObjectURL = vi.fn(() => 'blob:x');
    URL.revokeObjectURL = vi.fn();
    await wrapper.find('[data-people-export]').trigger('click');
    await flushPromises();
    expect(api.reports.export).toHaveBeenCalledWith(
      '9',
      expect.objectContaining({ status: 'complained', problem: true })
    );

    const next = wrapper
      .findAll('[data-people-pages] button')
      .find(button => button.text() === enResult.RESULT_JOURNEY.PEOPLE.NEXT);
    await next.trigger('click');
    await flushPromises();
    expect(api.reports.getRecipients).toHaveBeenLastCalledWith(
      '9',
      expect.objectContaining({ page: 2 })
    );
    wrapper.unmount();
  });

  it('"Ver lista de problemas" lands on the problem filter (showProblems)', async () => {
    const wrapper = mountPeople();
    await flushPromises();

    wrapper.vm.showProblems();
    await flushPromises();

    expect(api.reports.getRecipients).toHaveBeenLastCalledWith(
      '9',
      expect.objectContaining({ problem: true, search: '' })
    );
    expect(wrapper.find('[data-people-problem]').exists()).toBe(true);
    wrapper.unmount();
  });
});
