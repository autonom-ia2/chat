import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  loadDraft,
  saveDraft,
} from 'dashboard/components-next/CampaignJourney/campaignDraft';

// #993 front of #999: WhatsApp API (D7) and e-mail (D8–D13) inside the journey.
const api = vi.hoisted(() => ({
  list: vi.fn(),
  show: vi.fn(),
  variableSuggestions: vi.fn(),
  variableCoverage: vi.fn(),
  sampleContact: vi.fn(),
}));
const journey = vi.hoisted(() => ({
  create: vi.fn(),
  createWithFile: vi.fn(),
  preview: vi.fn(),
}));
const emailApi = vi.hoisted(() => ({
  show: vi.fn(),
  sendTest: vi.fn(),
  schedule: vi.fn(),
  sendNow: vi.fn(),
}));
const apiTemplates = vi.hoisted(() => ({ getTemplates: vi.fn() }));
vi.mock('dashboard/api/campaignJourney', () => ({
  audiencesAPI: api,
  journeyCampaignsAPI: journey,
}));
vi.mock('dashboard/api/emailCampaigns', () => ({ default: emailApi }));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: apiTemplates,
}));
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue',
  () => ({ default: { name: 'SMSCampaignDialog', render: () => null } })
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

const AUDIENCE = {
  id: 5,
  name: 'Corretoras parceiras',
  status: 'completed',
  valid_rows: 4,
  extra_columns: ['Data de Vencimento'],
  channels: {
    email: { enabled: true, count: 4 },
    whatsapp: { enabled: true, count: 3 },
    sms: { enabled: true, count: 3 },
  },
};
const INBOXES = [
  { id: 1, name: 'Site', channel_type: 'Channel::WebWidget' },
  { id: 11, name: 'SMS Hub2You', channel_type: 'Channel::Sms' },
  {
    id: 9,
    name: 'Atendimento API',
    channel_type: 'Channel::Api',
    additional_attributes: { campaign_channel_type: 'whatsapp_api' },
  },
  {
    id: 12,
    name: 'Respostas',
    channel_type: 'Channel::Email',
    email: 'respostas@empresa.com.br',
  },
];
const IDENTITY = {
  id: 4,
  domain: 'empresa.com.br',
  from_email: 'ola@empresa.com.br',
  status: 'verified',
};
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

const mountPage = () => {
  route.value = { query: {}, params: { accountId: 1 } };
  api.list.mockResolvedValue({
    data: { payload: [AUDIENCE], meta: { count: 1 } },
  });
  api.show.mockResolvedValue({ data: { payload: AUDIENCE } });
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({ email: 'gestora@empresa.com.br' }),
    },
    modules: {
      inboxes: module(
        {
          getInboxes: () => INBOXES,
          getFilteredWhatsAppTemplates: () => () => [],
        },
        { get: vi.fn() }
      ),
      emailSenderIdentities: module(
        { getIdentities: () => [IDENTITY] },
        { get: vi.fn() }
      ),
      globalConfig: module({
        get: () => ({
          emailCampaignEnabled: true,
          crmKanbanEnabled: true,
          whatsappApiCampaignsEnabled: true,
        }),
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

const toMessageStep = async (wrapper, channel) => {
  await wrapper.find('[data-audience-option="5"]').trigger('click');
  await wrapper.find('[data-test="continue-message"]').trigger('click');
  await wrapper.find(`[data-channel-card="${channel}"]`).trigger('click');
  await wrapper
    .find('[data-test="channel-form"] input[type="text"]')
    .setValue('Renovação — outubro');
};

beforeEach(() => {
  vi.useFakeTimers();
  [...Object.values(api), ...Object.values(journey), ...Object.values(emailApi)]
    .concat(apiTemplates.getTemplates)
    .forEach(fn => fn.mockReset());
  journey.preview.mockResolvedValue({
    data: { payload: { total: 3, receive: 2, reasons: { opted_out: 1 } } },
  });
  apiTemplates.getTemplates.mockResolvedValue({
    data: {
      payload: [
        { id: 3, name: 'Lembrete', body: 'Oi {{contact.first_name}}!' },
      ],
    },
  });
  push.mockClear();
  alert.mockClear();
  window.localStorage.clear();
});
afterEach(() => {
  vi.useRealTimers();
});

describe('Nova campanha — WhatsApp API (D7)', () => {
  it('inserts contact and audience fields, uses a saved template and sends the contract', async () => {
    journey.create.mockResolvedValue({ data: { id: 15 } });
    const wrapper = mountPage();
    await flushPromises();
    await toMessageStep(wrapper, 'whatsapp_api');

    const inbox = choice(wrapper, 'Sending inbox');
    expect(inbox.props('options')).toEqual([
      { value: 9, label: 'Atendimento API' },
    ]);
    inbox.vm.$emit('update:modelValue', 9);
    await flushPromises();
    expect(apiTemplates.getTemplates).toHaveBeenCalledWith(9);
    choice(wrapper, 'Use saved template').vm.$emit('update:modelValue', 3);
    await flushPromises();
    expect(wrapper.find('[data-test="api-message"]').element.value).toBe(
      'Oi {{contact.first_name}}!'
    );

    // Audience column with the key the server uses ("Data de Vencimento").
    await wrapper
      .find('[data-token="publico.data_de_vencimento"]')
      .trigger('click');
    expect(wrapper.find('[data-test="api-message"]').element.value).toContain(
      '{{publico.data_de_vencimento}}'
    );
    expect(wrapper.text()).toContain('Automatic pace');

    await vi.advanceTimersByTimeAsync(500);
    await flushPromises();
    expect(journey.preview).toHaveBeenLastCalledWith(
      expect.objectContaining({
        channel: 'whatsapp_api',
        campaign_import_id: 5,
      })
    );
    await wrapper.find('[data-test="continue-review"]').trigger('click');
    expect(wrapper.find('[data-test="receivers"]').text()).toBe('2');
    await wrapper.find('[data-test="open-confirmation"]').trigger('click');
    await wrapper.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();

    expect(journey.create).toHaveBeenCalledWith({
      campaign_import_id: 5,
      channel: 'whatsapp_api',
      campaign: {
        title: 'Renovação — outubro',
        inbox_id: 9,
        scheduled_at: null,
        message_body:
          'Oi {{contact.first_name}}!{{publico.data_de_vencimento}}',
        template_id: 3,
        variable_defaults: {},
      },
    });
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_index',
      query: { channel: 'whatsapp_api' },
    });
    wrapper.unmount();
  });
});

describe('Nova campanha — SMS (#1004, M3)', () => {
  it('SMS inbox, fields, parts counter, preview as SMS and the contract call', async () => {
    journey.create.mockResolvedValue({ data: { id: 18 } });
    api.sampleContact.mockResolvedValue({
      data: {
        payload: {
          name: 'Ana Souza',
          extra_values: { 'Data de Vencimento': '10/2026' },
        },
      },
    });
    const wrapper = mountPage();
    await flushPromises();
    await toMessageStep(wrapper, 'sms');

    const inbox = choice(wrapper, 'SMS inbox');
    expect(inbox.props('options')).toEqual([
      { value: 11, label: 'SMS Hub2You' },
    ]);
    inbox.vm.$emit('update:modelValue', 11);
    await wrapper.find('[data-test="sms-message"]').setValue('Oi ');
    await wrapper
      .find('[data-sms-token="contact.first_name"]')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-test="sms-counter"]').text()).toBe(
      '25 characters · 1 SMS'
    );
    await wrapper
      .find('[data-test="sms-message"]')
      .setValue('Olá {{contact.first_name}}');
    expect(wrapper.text()).toContain('Up to 70 per SMS (UCS-2)');
    expect(wrapper.find('[data-test="sms-preview-text"]').text()).toBe(
      'Olá Ana'
    );

    await vi.advanceTimersByTimeAsync(500);
    await flushPromises();
    await wrapper.find('[data-test="continue-review"]').trigger('click');
    await wrapper.find('[data-test="open-confirmation"]').trigger('click');
    await wrapper.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();

    expect(journey.create).toHaveBeenCalledWith({
      campaign_import_id: 5,
      channel: 'sms',
      campaign: {
        title: 'Renovação — outubro',
        inbox_id: 11,
        scheduled_at: null,
        message: 'Olá {{contact.first_name}}',
        variable_defaults: {},
      },
    });
    wrapper.unmount();
  });
});

describe('Nova campanha — e-mail (D8–D13)', () => {
  it('creates the draft with sender and reply inbox, then opens the existing editor', async () => {
    journey.create.mockResolvedValue({ data: { id: 31 } });
    emailApi.show.mockResolvedValue({
      data: { payload: { id: 31, subject: '', send_readiness: {} } },
    });
    const wrapper = mountPage();
    await flushPromises();
    await toMessageStep(wrapper, 'email');

    choice(wrapper, 'Sender').vm.$emit('update:modelValue', 'identity:4');
    choice(wrapper, 'Replies go to the inbox').vm.$emit(
      'update:modelValue',
      12
    );
    await flushPromises();
    await wrapper.find('[data-test="email-create"]').trigger('click');
    await flushPromises();

    expect(journey.create).toHaveBeenCalledWith({
      campaign_import_id: 5,
      channel: 'email',
      campaign: {
        title: 'Renovação — outubro',
        delivery_mode: 'ses',
        sender_identity_id: 4,
        from_email: 'ola@empresa.com.br',
        reply_to_inbox_id: 12,
      },
    });
    expect(loadDraft(1)).toMatchObject({ emailCampaignId: 31 });

    await wrapper.find('[data-test="email-open-editor"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_email_builder',
      params: { campaignId: 31 },
      // D12: marks the visit so the editor's exit comes back to the journey.
      query: { journey: '1' },
    });
    wrapper.unmount();
  });

  it('back from the editor: review with readiness, test to me and schedule', async () => {
    saveDraft(1, {
      title: 'Novidades',
      audienceId: 5,
      channel: 'email',
      emailSender: 'identity:4',
      emailCampaignId: 31,
      when: 'later',
      scheduledAt: '2027-01-10T08:00',
      step: 3,
    });
    emailApi.show.mockResolvedValue({
      data: {
        payload: {
          id: 31,
          subject: 'Três novidades',
          from_name: 'Hub2You',
          from_email: 'ola@empresa.com.br',
          send_readiness: {
            checks: { subject: true, content: true, sender: true },
          },
        },
      },
    });
    emailApi.sendTest.mockResolvedValue({});
    emailApi.schedule.mockResolvedValue({});
    const wrapper = mountPage();
    await flushPromises();
    await vi.advanceTimersByTimeAsync(500);
    await flushPromises();

    expect(wrapper.find('[data-review-block="content"]').text()).toContain(
      'Subject: Três novidades'
    );
    expect(wrapper.find('[data-test="review-checks"]').text()).toContain(
      'Subject filled'
    );
    await wrapper.find('[data-test="test-send"]').trigger('click');
    await flushPromises();
    expect(emailApi.sendTest).toHaveBeenCalledWith(
      31,
      'gestora@empresa.com.br'
    );

    await wrapper.find('[data-test="open-confirmation"]').trigger('click');
    await wrapper.find('[data-test="dialog-confirm"]').trigger('click');
    await flushPromises();
    expect(emailApi.schedule).toHaveBeenCalledWith(
      31,
      '2027-01-10T11:00:00.000Z'
    );
    expect(emailApi.sendNow).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});

describe('Chat ao vivo shortcut (M5)', () => {
  it('opens its own flow from the Público step', async () => {
    const wrapper = mountPage();
    await flushPromises();
    await wrapper.find('[data-test="live-chat-shortcut"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_live_chat_new',
    });
    wrapper.unmount();
  });
});
