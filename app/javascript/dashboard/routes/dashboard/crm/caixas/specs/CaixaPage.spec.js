import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import CaixaPage from '../pages/CaixaPage.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1570 — o editor da caixa: os agentes de IA seguem a Fase 2 do payload da
// conta (inclusive quando ela chega depois da caixa) e a recusa "principal
// parado" do servidor vira uma frase simples, na etapa de quem cuida.
const conta = vi.hoisted(() => ({ fase2: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed, reactive } = await import('vue');
  const estado = reactive(conta);
  const getters = {
    'accounts/getAccount': () => () => ({
      autonomia_agents_fase2: estado.fase2,
    }),
    getCurrentAccountId: () => 1,
    'inboxes/getInboxById': () => () => ({}),
  };
  conta.estado = estado;
  return { useMapGetter: nome => computed(() => getters[nome]()) };
});

const api = vi.hoisted(() => ({
  buscar: vi.fn(),
  salvar: vi.fn(),
  quemRecebe: vi.fn(),
}));
vi.mock('dashboard/api/crmCaixas', () => ({ default: api }));

const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const rota = vi.hoisted(() => ({
  params: { accountId: 1, inboxId: 7 },
  query: { etapa: '2' },
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));

const FUNIS = [
  { id: 1, name: 'Comercial', stages: [{ id: 11, name: 'Novo' }] },
];

const CAIXA = {
  inbox: { id: 7, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
  crm_enabled: true,
  pipeline_ids: [1],
  default_stage_id: 11,
  subject_ai_mode: 'off',
  auto_create_card: true,
  visibility_mode: 'all_inbox_cards',
  agent_bot: { id: 9, name: 'Clara' },
  people: [],
  ai_agents: {
    porta: { id: 9, name: 'Clara' },
    pode_mudar: true,
    areas: [],
    disponiveis: [{ id: 2, name: 'Marta', parado: false }],
  },
};

const render = () =>
  mount(CaixaPage, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          fallbackLocale: false,
          messages: { en, pt_BR },
        }),
      ],
    },
  });

describe('CaixaPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    conta.estado.fase2 = null;
    rota.query.etapa = '2';
    api.buscar.mockResolvedValue({ caixa: CAIXA, funis: FUNIS });
    api.quemRecebe.mockResolvedValue({ triagem: [], funis: { 1: [] } });
  });

  it('shows the AI agents when phase 2 arrives in the account payload after the inbox', async () => {
    const wrapper = render();
    await flushPromises();

    expect(wrapper.find('[data-robo]').exists()).toBe(true);
    expect(wrapper.find('[data-porta]').exists()).toBe(false);

    conta.estado.fase2 = true;
    await nextTick();

    expect(wrapper.find('[data-robo]').exists()).toBe(false);
    expect(wrapper.find('[data-porta]').text()).toContain('Clara');
  });

  it('hides the AI agents when phase 2 is turned off in the account', async () => {
    conta.estado.fase2 = true;
    const wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-porta]').text()).toContain('Clara');

    conta.estado.fase2 = false;
    await nextTick();

    expect(wrapper.find('[data-porta]').exists()).toBe(false);
    expect(wrapper.find('[data-robo]').exists()).toBe(true);
  });

  it.each([
    [
      'crm.caixas.principal_parado',
      'O agente principal desta caixa não está atendendo. Para pôr um agente da equipe aqui, ligue o principal antes.',
    ],
    [
      'crm.caixas.robo_externo',
      'Um agente externo atende nesta caixa. O agente da equipe ainda não entra em caixa com agente externo.',
    ],
    [
      'crm.caixas.agente_rascunho',
      'Este agente ainda é rascunho; termine de criar antes.',
    ],
    [
      'crm.caixas.agente_invalido',
      'Não deu para salvar os agentes de IA. Recarregue a página e tente de novo.',
    ],
  ])(
    'turns the server refusal %s into a plain sentence',
    async (code, frase) => {
      conta.estado.fase2 = true;
      rota.query.etapa = '4';
      api.salvar.mockRejectedValue({ response: { data: { error: { code } } } });
      const wrapper = render();
      await flushPromises();

      await wrapper.get('[data-salvar]').trigger('click');
      await flushPromises();

      expect(alerta).toHaveBeenCalledWith(frase);
      // Volta para quem cuida, onde se resolve.
      expect(wrapper.find('[data-porta]').exists()).toBe(true);
    }
  );
});

// #1140 — quem recebe vem do servidor nas etapas 3 e 4, com o que está marcado.
describe('CaixaPage: quem recebe', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    conta.estado.fase2 = null;
    api.buscar.mockResolvedValue({ caixa: CAIXA, funis: FUNIS });
    api.quemRecebe.mockResolvedValue({ triagem: [], funis: { 1: [] } });
  });

  it('does not ask while the person is choosing who takes care of what', async () => {
    rota.query.etapa = '2';
    render();
    await flushPromises();

    expect(api.quemRecebe).not.toHaveBeenCalled();
  });

  it('asks the server once on the check step, with what is marked', async () => {
    rota.query.etapa = '4';
    const wrapper = render();
    await flushPromises();

    expect(api.quemRecebe).toHaveBeenCalledTimes(1);
    expect(api.quemRecebe).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ pipeline_ids: [1], people: [] })
    );
    expect(wrapper.find('[data-ninguem-recebe]').text()).toContain('Comercial');
  });

  it('asks again after an error when the person leaves and comes back to step 3', async () => {
    rota.query.etapa = '4';
    api.quemRecebe.mockRejectedValueOnce(new Error('falhou'));
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain(
      'Não deu para conferir quem recebe agora.'
    );

    const voltar = () =>
      wrapper
        .findAll('footer button')
        .find(botao => botao.text() === 'Voltar')
        .trigger('click');
    await voltar();
    await voltar();
    await flushPromises();
    await wrapper.get('[data-continuar]').trigger('click');
    await flushPromises();

    expect(api.quemRecebe).toHaveBeenCalledTimes(2);
  });
});
