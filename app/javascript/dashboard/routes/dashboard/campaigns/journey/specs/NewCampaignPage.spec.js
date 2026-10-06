import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  loadDraft,
  saveDraft,
} from 'dashboard/components-next/CampaignJourney/campaignDraft';

const api = vi.hoisted(() => ({
  list: vi.fn(),
  show: vi.fn(),
  variableSuggestions: vi.fn(),
  variableCoverage: vi.fn(),
  sampleContact: vi.fn(),
}));
const create = vi.hoisted(() => vi.fn());
const preview = vi.hoisted(() => vi.fn());
vi.mock('dashboard/api/campaignJourney', () => ({
  audiencesAPI: api,
  journeyCampaignsAPI: { create, preview },
}));

const stub = name => ({ default: { name, render: () => null } });
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue',
  () => stub('EmailCampaignDialog')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppApiCampaign/WhatsAppApiCampaignDialog.vue',
  () => stub('WhatsAppApiCampaignDialog')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue',
  () => stub('SMSCampaignDialog')
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue',
  () => stub('LiveChatCampaignDialog')
);

const route = vi.hoisted(() => ({ value: null }));
const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => route.value,
  useRouter: () => ({ push }),
}));
const alert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

const { default: NewCampaignPage } = await import('../NewCampaignPage.vue');

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const PHONE_AUDIENCE = {
  id: 5,
  name: 'Auto vencendo out/26',
  status: 'completed',
  valid_rows: 98,
  extra_columns: ['Vencimento'],
  channels: {
    email: { enabled: false, count: 0 },
    whatsapp: { enabled: true, count: 98 },
  },
  created_at: '2026-10-05T12:00:00Z',
};
const EMAIL_AUDIENCE = {
  id: 6,
  name: 'Corretoras parceiras',
  status: 'completed',
  valid_rows: 3,
  extra_columns: [],
  channels: {
    email: { enabled: true, count: 3 },
    whatsapp: { enabled: false, count: 0 },
  },
};
const NOT_SAVED = { id: 7, name: 'Ainda lendo', status: 'ready_to_confirm' };

const TEMPLATE = {
  id: 9,
  name: 'renovacao_auto',
  namespace: 'ns',
  category: 'MARKETING',
  language: 'pt_BR',
  status: 'approved',
  components: [{ type: 'BODY', text: 'Olá, {{1}}! O seguro vence em {{2}}.' }],
};
const INBOXES = [
  {
    id: 7,
    name: 'Hub2You Seguros',
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
  },
  {
    id: 8,
    name: 'WhatsApp antigo',
    channel_type: 'Channel::Whatsapp',
    provider: 'default',
  },
  { id: 3, name: 'SMS', channel_type: 'Channel::Sms' },
];

const DialogStub = {
  name: 'Dialog',
  props: ['title'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div data-test="confirm-dialog">{{ title }}<button data-test="dialog-confirm" @click="$emit(\'confirm\')" /></div>',
};

const module = (getters, actions = {}) => ({
  namespaced: true,
  getters,
  actions,
});

// The page asks the server for saved audiences (saved=true, q); NOT_SAVED never comes back.
const mountPage = ({ imports = [PHONE_AUDIENCE], query = {} } = {}) => {
  route.value = { query, params: { accountId: 1 } };
  const saved = imports.filter(item => item.status === 'completed');
  api.list.mockImplementation(({ q }) => {
    const found = saved.filter(item =>
      item.name.toLowerCase().includes(q.toLowerCase())
    );
    return Promise.resolve({
      data: { payload: found, meta: { count: found.length } },
    });
  });
  api.show.mockImplementation(id =>
    Promise.resolve({
      data: { payload: imports.find(item => item.id === Number(id)) },
    })
  );
  const store = createStore({
    getters: { getCurrentAccountId: () => 1 },
    modules: {
      inboxes: module(
        {
          getInboxes: () => INBOXES,
          getFilteredWhatsAppTemplates: () => () => [TEMPLATE],
        },
        { get: vi.fn() }
      ),
      emailSenderIdentities: module({ getIdentities: () => [] }),
      globalConfig: module({
        get: () => ({ emailCampaignEnabled: false }),
      }),
      accounts: module({
        isFeatureEnabledonAccount: () => () => true,
        getAccount: () => () => ({ id: 1, timezone: 'America/Sao_Paulo' }),
      }),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: enJourney },
  });
  return mount(NewCampaignPage, {
    attachTo: document.body,
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': { template: '<a><slot /></a>' },
        Dialog: DialogStub,
      },
    },
  });
};

const choice = (wrapper, label) =>
  wrapper
    .findAllComponents(ChoiceSelect)
    .find(item => item.props('ariaLabel') === label);

beforeEach(() => {
  vi.useFakeTimers();
  Object.values(api).forEach(fn => fn.mockReset());
  api.sampleContact.mockRejectedValue({ response: { status: 404 } });
  api.variableSuggestions.mockResolvedValue({ data: { payload: [] } });
  api.variableCoverage.mockResolvedValue({ data: { payload: null } });
  create.mockReset();
  preview.mockReset();
  preview.mockResolvedValue({ data: { payload: null } });
  push.mockClear();
  alert.mockClear();
  window.localStorage.clear();
});
afterEach(() => {
  vi.useRealTimers();
});

describe('Nova campanha — Passo 1 (PRD §6.2)', () => {
  it('J1: lists only saved audiences, with channel badges and counts', async () => {
    const wrapper = mountPage({ imports: [PHONE_AUDIENCE, NOT_SAVED] });
    await flushPromises();

    expect(api.list).toHaveBeenCalledWith({ saved: true, q: '', page: 1 });
    const options = wrapper.findAll('[data-audience-option]');
    expect(
      options.map(option => option.attributes('data-audience-option'))
    ).toEqual(['5']);
    expect(options[0].find('[data-badge="whatsapp"]').text()).toBe(
      'WhatsApp · 98'
    );
    expect(wrapper.find('[data-step="1"]').attributes('aria-current')).toBe(
      'step'
    );
    wrapper.unmount();
  });

  it('J2: without audiences, one sentence and one button that keeps the draft', async () => {
    const wrapper = mountPage({ imports: [] });
    await flushPromises();

    const empty = wrapper.find('[data-test="audience-step-empty"]');
    expect(empty.text()).toContain("You don't have a list of people yet.");
    expect(empty.findAll('button')).toHaveLength(1);
    await empty.find('[data-test="create-audience"]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_audience_new',
      query: { from: 'campaign' },
    });
    expect(loadDraft(1)).not.toBeNull();
    wrapper.unmount();
  });

  it('J3: back from Novo público, the draft returns with the new audience selected', async () => {
    saveDraft(1, { title: 'Renovação auto — outubro', step: 1 });
    const wrapper = mountPage({ query: { audience: '5', returned: '1' } });
    await flushPromises();

    expect(wrapper.find('[data-test="returned"]').text()).toContain(
      'Auto vencendo out/26'
    );
    expect(
      wrapper.find('[data-audience-option="5"]').attributes('aria-pressed')
    ).toBe('true');
    expect(loadDraft(1)).toMatchObject({
      title: 'Renovação auto — outubro',
      audienceId: 5,
    });
    wrapper.unmount();
  });

  it('F3: "Usar em nova campanha" starts a fresh draft with the audience selected', async () => {
    saveDraft(1, { title: 'Rascunho antigo' });
    const wrapper = mountPage({ query: { audience: '5' } });
    await flushPromises();

    expect(
      wrapper.find('[data-audience-option="5"]').attributes('aria-pressed')
    ).toBe('true');
    expect(wrapper.find('[data-test="returned"]').exists()).toBe(false);
    expect(loadDraft(1)).toMatchObject({ title: '', audienceId: 5 });
    wrapper.unmount();
  });
});

describe('Nova campanha — Passo 2 and 3 (PRD §6.3, §6.4)', () => {
  it('J4: an e-mail-only audience cannot go by WhatsApp and says why', async () => {
    const wrapper = mountPage({ imports: [EMAIL_AUDIENCE] });
    await flushPromises();

    await wrapper.find('[data-audience-option="6"]').trigger('click');
    await wrapper.find('[data-test="continue-message"]').trigger('click');

    const official = wrapper.find('[data-channel-card="whatsapp_official"]');
    expect(official.attributes('disabled')).toBeDefined();
    expect(official.find('[data-test="card-hint"]').text()).toBe(
      'This audience has no mobile.'
    );
    // #1004: SMS has its own badge.
    const sms = wrapper.find('[data-channel-card="sms"]');
    expect(sms.text()).toContain('This audience has no SMS on.');
    wrapper.unmount();
  });

  it('B1, B1b: prefilled suggestion, coverage warning, review and the contract call', async () => {
    api.variableSuggestions.mockResolvedValue({
      data: {
        payload: [
          { key: '1', source: null },
          { key: '2', source: { source: 'extra', column: 'Vencimento' } },
        ],
      },
    });
    api.variableCoverage.mockResolvedValue({
      data: {
        payload: {
          included_count: 96,
          excluded_count: 2,
          missing_by_variable: { 2: 2 },
        },
      },
    });
    create.mockResolvedValue({ data: { id: 31, recipients_count: 96 } });
    preview.mockResolvedValue({
      data: {
        payload: {
          total: 98,
          receive: 96,
          reasons: { missing_variables: 2 },
          missing_by_variable: { 2: 2 },
        },
      },
    });
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-audience-option="5"]').trigger('click');
    await wrapper.find('[data-test="continue-message"]').trigger('click');
    expect(wrapper.find('[data-step="2"]').attributes('aria-current')).toBe(
      'step'
    );
    await wrapper
      .find('[data-channel-card="whatsapp_official"]')
      .trigger('click');
    await wrapper
      .find('[data-test="official-form"] input[type="text"]')
      .setValue('Renovação auto — outubro');
    expect(wrapper.text()).toContain(
      'Whoever replies gets the tag Campaign: Renovação auto — outubro on the CRM card.'
    );

    const inbox = choice(wrapper, 'Sending inbox');
    expect(inbox.props('options')).toEqual([
      { value: 7, label: 'Hub2You Seguros' },
    ]);
    inbox.vm.$emit('update:modelValue', 7);
    await flushPromises();
    choice(wrapper, 'Approved template').vm.$emit('update:modelValue', 9);
    await flushPromises();

    expect(api.variableSuggestions).toHaveBeenCalledWith(5, [
      { key: '1', label: 'Olá,' },
      { key: '2', label: 'O seguro vence em' },
    ]);
    const second = wrapper.find('[data-variable="2"]');
    expect(second.find('[data-test="suggested"]').text()).toBe('Suggested');
    expect(
      wrapper.find('[data-test="continue-review"]').attributes('disabled')
    ).toBeDefined();

    choice(wrapper, 'Where {{1}} comes from').vm.$emit(
      'update:modelValue',
      'contact:first_name'
    );
    await flushPromises();
    await vi.advanceTimersByTimeAsync(500);
    await flushPromises();

    expect(api.variableCoverage).toHaveBeenLastCalledWith(5, {
      mapping: {
        1: { source: 'name' },
        2: { source: 'extra', column: 'Vencimento' },
      },
      defaults: {},
    });
    expect(wrapper.find('[data-test="coverage-warning"]').text()).toContain(
      '2 people are left out: missing {{2}}'
    );
    expect(wrapper.find('[data-test="preview-text"]').text()).toBe(
      'Olá, [First name of the contact]! O seguro vence em [Vencimento].'
    );

    await wrapper.find('[data-test="continue-review"]').trigger('click');
    expect(wrapper.find('[data-step="3"]').attributes('aria-current')).toBe(
      'step'
    );
    // Decision of 05/10: the exact number of the server, each person once.
    expect(preview).toHaveBeenLastCalledWith({
      campaign_import_id: 5,
      channel: 'whatsapp_cloud',
      variable_bindings: {
        1: { source: 'contact', value: 'first_name' },
        2: { source: 'column', value: 'Vencimento' },
      },
      variable_defaults: {},
    });
    expect(wrapper.find('[data-test="receivers"]').text()).toBe('96');
    expect(wrapper.find('[data-reason="missing_variables"]').text()).toContain(
      '−2'
    );
    expect(wrapper.find('[data-test="review-crm"]').text()).toContain(
      'Campaign: Renovação auto — outubro'
    );

    await wrapper.find('[data-test="open-confirmation"]').trigger('click');
    expect(wrapper.find('[data-test="confirm-dialog"]').text()).toContain(
      'Send now to 96 people?'
    );
    await wrapper.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();

    expect(create).toHaveBeenCalledWith({
      campaign_import_id: 5,
      channel: 'whatsapp_cloud',
      campaign: {
        title: 'Renovação auto — outubro',
        inbox_id: 7,
        scheduled_at: null,
        template_params: {
          name: 'renovacao_auto',
          namespace: 'ns',
          category: 'MARKETING',
          language: 'pt_BR',
          processed_params: { body: { 1: '', 2: '' } },
        },
        variable_bindings: {
          1: { source: 'contact', value: 'first_name' },
          2: { source: 'column', value: 'Vencimento' },
        },
        variable_defaults: {},
      },
    });
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_index',
      query: { channel: 'whatsapp_official' },
    });
    expect(loadDraft(1)).toBeNull();
    wrapper.unmount();
  });

  it('schedules in the account time zone and shows readable API errors', async () => {
    saveDraft(1, {
      title: 'Renovação',
      audienceId: 5,
      channel: 'whatsapp_official',
      inboxId: 7,
      templateId: 9,
      bindings: {
        1: { source: 'fixed', value: 'cliente' },
        2: { source: 'fixed', value: 'outubro' },
      },
      when: 'later',
      scheduledAt: '2027-01-10T09:00',
      step: 3,
    });
    create.mockRejectedValue({
      response: { status: 422, data: { code: 'invalid_variable_bindings' } },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-step="3"]').attributes('aria-current')).toBe(
      'step'
    );
    expect(wrapper.text()).toContain('Date and time (America/Sao_Paulo)');
    await wrapper.find('[data-test="open-confirmation"]').trigger('click');
    await wrapper.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();

    expect(create.mock.calls[0][0].campaign.scheduled_at).toBe(
      '2027-01-10T12:00:00.000Z'
    );
    expect(wrapper.find('[data-test="review-aside"]').text()).toContain(
      'Some part of the message has no valid source.'
    );
    expect(loadDraft(1)).not.toBeNull();
    wrapper.unmount();
  });

  it('D3, G2: no batch choice and no native select on any step', async () => {
    saveDraft(1, {
      title: 'Renovação',
      audienceId: 5,
      channel: 'whatsapp_official',
      inboxId: 7,
      templateId: 9,
      bindings: {
        1: { source: 'fixed', value: 'cliente' },
        2: { source: 'fixed', value: 'outubro' },
      },
      step: 2,
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('select').exists()).toBe(false);
    await wrapper.find('[data-test="continue-review"]').trigger('click');
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.text().toLowerCase()).not.toContain('batch');
    wrapper.unmount();
  });

  it('J1: searches saved audiences on the server', async () => {
    const wrapper = mountPage({ imports: [PHONE_AUDIENCE, EMAIL_AUDIENCE] });
    await flushPromises();

    await wrapper.find('[data-test="audience-search"]').setValue('corretoras');
    await vi.advanceTimersByTimeAsync(400);
    await flushPromises();

    expect(api.list).toHaveBeenLastCalledWith({
      saved: true,
      q: 'corretoras',
      page: 1,
    });
    expect(
      wrapper
        .findAll('[data-audience-option]')
        .map(option => option.attributes('data-audience-option'))
    ).toEqual(['6']);
    wrapper.unmount();
  });

  it('B8: who refused messages is out of "vão receber" (server preview)', async () => {
    preview.mockResolvedValue({
      data: { payload: { total: 98, receive: 95, reasons: { opted_out: 3 } } },
    });
    saveDraft(1, {
      title: 'Renovação',
      audienceId: 5,
      channel: 'whatsapp_official',
      inboxId: 7,
      templateId: 9,
      bindings: {
        1: { source: 'fixed', value: 'cliente' },
        2: { source: 'fixed', value: 'outubro' },
      },
      step: 3,
    });
    const wrapper = mountPage();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(500);
    await flushPromises();

    expect(wrapper.find('[data-reason="opted_out"]').text()).toContain('−3');
    expect(wrapper.find('[data-test="receivers"]').text()).toBe('95');
    wrapper.unmount();
  });
});
