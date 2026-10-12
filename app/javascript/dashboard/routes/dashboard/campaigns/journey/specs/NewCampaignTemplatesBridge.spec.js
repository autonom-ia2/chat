import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import enModelos from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  loadDraft,
  saveDraft,
} from 'dashboard/components-next/CampaignJourney/campaignDraft';
import { modeloDaMeta } from '../../modelos/api/daMeta';

// Ponte Campanha ↔ Modelos (#1332): ?modelo=&caixa=, rascunho guardado, variáveis
// ligadas pelo catálogo (#1331), "Enviar agora" bloqueado com o modelo em análise.
// Com a flag desligada a campanha é a de sempre: NewCampaignPage.spec.js e
// NewCampaignChannels.spec.js rodam com ela desligada e seguem iguais.

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

const modelosApi = vi.hoisted(() => ({
  listarCaixasDaCampanha: vi.fn(),
  listarModelos: vi.fn(),
  custoPorEnvio: vi.fn(),
}));
vi.mock('../../modelos/api/modelosWhatsapp', () => ({ default: modelosApi }));

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
const replace = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => route.value,
  useRouter: () => ({ push, replace }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

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
  name: 'Clientes ativos',
  status: 'completed',
  valid_rows: 40,
  extra_columns: ['Vencimento'],
  channels: {
    email: { enabled: false, count: 0 },
    whatsapp: { enabled: true, count: 40 },
  },
};

// O modelo como a API de Modelos (#1330) devolve: lista da Meta + perfil.
const TEMPLATE = {
  id: '1048213377610300',
  name: 'boas_vindas_outubro',
  language: 'pt_BR',
  status: 'PENDING',
  category: 'MARKETING',
  components: [
    {
      type: 'BODY',
      text: 'Olá, {{1}}! Que bom ter você na {{2}}.',
      example: { body_text: [['Ana', 'Hub2you']] },
    },
  ],
  friendly_name: 'Boas-vindas de outubro',
  fields: { 1: 'cliente.primeiro_nome', 2: 'minha_empresa.nome' },
  header_media: {},
  system_owner: null,
};
const CAIXAS = [
  {
    id: 7,
    nome: 'Atendimento',
    telefone: '+55 11 4000-0001',
    conta: { id: 7, nome: 'Hub2you' },
    situacao: 'conectada',
  },
  {
    id: 8,
    nome: 'Recife',
    telefone: '+55 81 4000-0004',
    conta: { id: 7, nome: 'Hub2you' },
    situacao: 'reconectar',
  },
];
const MODELO = modeloDaMeta(TEMPLATE, {
  id: 7,
  conta: { id: 7, nome: 'Hub2you' },
  numeros: [7, 8],
  envios: {},
});
const STORE_INBOXES = [
  {
    id: 7,
    name: 'Atendimento',
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
  },
];

const module = (getters, actions = {}) => ({
  namespaced: true,
  getters,
  actions,
});

const mountPage = ({ query = {}, flag = true } = {}) => {
  route.value = { query, params: { accountId: 1 } };
  api.list.mockResolvedValue({
    data: { payload: [AUDIENCE], meta: { count: 1 } },
  });
  api.show.mockResolvedValue({ data: { payload: AUDIENCE } });
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({ id: 1, accounts: [] }),
      getCurrentCustomRoleId: () => null,
    },
    modules: {
      inboxes: module(
        {
          getInboxes: () => STORE_INBOXES,
          getFilteredWhatsAppTemplates: () => () => [],
        },
        { get: vi.fn() }
      ),
      emailSenderIdentities: module({ getIdentities: () => [] }),
      globalConfig: module({ get: () => ({ emailCampaignEnabled: false }) }),
      accounts: module({
        isFeatureEnabledonAccount: () => (_accountId, name) =>
          name === 'whatsapp_templates_journey' ? flag : true,
        getAccount: () => () => ({ id: 1, name: 'Hub2you' }),
      }),
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...enJourney, ...enModelos } },
  });
  return mount(NewCampaignPage, {
    attachTo: document.body,
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': { template: '<a><slot /></a>' },
        Dialog: { template: '<div />', methods: { open() {}, close() {} } },
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
  Object.values(modelosApi).forEach(fn => fn.mockReset());
  api.sampleContact.mockRejectedValue({ response: { status: 404 } });
  api.variableSuggestions.mockResolvedValue({ data: { payload: [] } });
  api.variableCoverage.mockResolvedValue({ data: { payload: null } });
  preview.mockResolvedValue({ data: { payload: { total: 40, receive: 40 } } });
  modelosApi.listarCaixasDaCampanha.mockResolvedValue(CAIXAS);
  modelosApi.listarModelos.mockResolvedValue([MODELO]);
  modelosApi.custoPorEnvio.mockResolvedValue({ valor: 0.3217, moeda: 'BRL' });
  push.mockClear();
  replace.mockClear();
  window.localStorage.clear();
});
afterEach(() => {
  vi.useRealTimers();
});

describe('Nova campanha com a ponte de Modelos (#1332)', () => {
  it('opens with the template, binds the catalog fields and blocks "send now" while in review', async () => {
    const wrapper = mountPage({
      query: { modelo: TEMPLATE.id, caixa: '7' },
    });
    await flushPromises();

    await wrapper.find('[data-audience-option="5"]').trigger('click');
    await wrapper.find('[data-test="continue-message"]').trigger('click');
    await flushPromises();

    // A caixa que precisa reconectar aparece desativada, com o motivo.
    expect(choice(wrapper, 'Sending inbox').props('options')).toEqual([
      { value: 7, label: 'Atendimento', disabled: false },
      { value: 8, label: 'Recife · needs reconnecting', disabled: true },
    ]);
    expect(wrapper.find('[data-ponte-reconectar]').exists()).toBe(true);
    expect(wrapper.find('[data-ponte-em-analise]').exists()).toBe(true);

    const bound = key =>
      wrapper
        .find(`[data-variable="${key}"]`)
        .findComponent(ChoiceSelect)
        .props('modelValue');
    expect(bound('1')).toBe('field:cliente.primeiro_nome');
    expect(bound('2')).toBe('field:minha_empresa.nome');
    expect(wrapper.find('[data-variable="1"]').text()).toContain(
      'Customer name'
    );

    await wrapper
      .find('[data-test="official-form"] input[type="text"]')
      .setValue('Boas-vindas de outubro');
    await vi.advanceTimersByTimeAsync(500);
    await flushPromises();
    expect(api.variableCoverage).toHaveBeenLastCalledWith(5, {
      mapping: { 1: { source: 'name' } },
      defaults: {},
    });

    await wrapper.find('[data-test="continue-review"]').trigger('click');
    await flushPromises();

    expect(preview).toHaveBeenLastCalledWith(
      expect.objectContaining({
        variable_bindings: {
          1: { source: 'field', value: 'cliente.primeiro_nome' },
          2: { source: 'field', value: 'minha_empresa.nome' },
        },
      })
    );
    expect(wrapper.find('[data-when="now"]').attributes('disabled')).toBe('');
    expect(wrapper.find('[data-test="now-blocked"]').exists()).toBe(true);
    expect(wrapper.find('[data-revisao-modelo]').text()).toContain(
      'Boas-vindas de outubro'
    );
    expect(modelosApi.custoPorEnvio).toHaveBeenCalledWith('divulgacao');
    wrapper.unmount();
  });

  it('back from Modelos (?returned=1) keeps the stored draft and picks the new template', async () => {
    saveDraft(1, {
      title: 'Campanha guardada',
      audienceId: 5,
      channel: 'whatsapp_official',
      inboxId: 7,
      step: 2,
    });
    const wrapper = mountPage({
      query: { returned: '1', modelo: TEMPLATE.id, caixa: '7' },
    });
    await flushPromises();

    expect(loadDraft(1)).toMatchObject({
      title: 'Campanha guardada',
      inboxId: 7,
      templateId: TEMPLATE.id,
      step: 2,
    });
    wrapper.unmount();
  });

  it('a box without a ready template offers to create one, keeping the draft', async () => {
    modelosApi.listarModelos.mockResolvedValue([]);
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-audience-option="5"]').trigger('click');
    await wrapper.find('[data-test="continue-message"]').trigger('click');
    await wrapper
      .find('[data-channel-card="whatsapp_official"]')
      .trigger('click');
    choice(wrapper, 'Sending inbox').vm.$emit('update:modelValue', 7);
    await flushPromises();

    await wrapper.find('[data-criar-modelo]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'modelos_whatsapp_novo',
      query: { from: 'campaign', caixa: '7' },
    });
    expect(loadDraft(1)).toMatchObject({ audienceId: 5, inboxId: 7 });
    wrapper.unmount();
  });

  it('without permission to see templates, the campaign stays the usual one', async () => {
    modelosApi.listarModelos.mockRejectedValue(new Error('401'));
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-audience-option="5"]').trigger('click');
    await wrapper.find('[data-test="continue-message"]').trigger('click');
    await wrapper
      .find('[data-channel-card="whatsapp_official"]')
      .trigger('click');

    expect(choice(wrapper, 'Sending inbox').props('options')).toEqual([
      { value: 7, label: 'Atendimento' },
    ]);
    expect(wrapper.find('[data-ponte-reconectar]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('with the flag off, the templates screen is never asked', async () => {
    const wrapper = mountPage({ flag: false });
    await flushPromises();

    expect(modelosApi.listarModelos).not.toHaveBeenCalled();
    expect(modelosApi.listarCaixasDaCampanha).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
