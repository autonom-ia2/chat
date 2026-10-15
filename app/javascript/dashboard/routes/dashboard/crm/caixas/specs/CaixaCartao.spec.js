import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CaixaCartao from '../components/CaixaCartao.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1570 — "Quem cuida" mostra os agentes de IA só com a Fase 2 dos Agentes
// ligada no payload da conta (`autonomia_agents_fase2`), a mesma fonte da tela
// dos Agentes; a caixa trazer `ai_agents` não basta.
const conta = vi.hoisted(() => ({ fase2: false }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    'accounts/getAccount': () => () => ({
      autonomia_agents_fase2: conta.fase2,
    }),
    getCurrentAccountId: () => 1,
  };
  return { useMapGetter: nome => computed(() => getters[nome]()) };
});

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
  agent_bot: { id: 99, name: 'Robô antigo' },
  people: [],
  ai_agents: {
    porta: { id: 9, name: 'Clara' },
    pode_mudar: true,
    areas: [
      {
        id: 1,
        name: 'Maria',
        pipeline_ids: [1],
        parado: false,
        ultima_caixa: true,
      },
    ],
    disponiveis: [],
  },
};

const render = () =>
  mount(CaixaCartao, {
    props: { caixa: CAIXA, funis: FUNIS },
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

describe('CaixaCartao', () => {
  beforeEach(() => {
    conta.fase2 = false;
  });

  it('with phase 2 on in the account shows the AI agents of the inbox', () => {
    conta.fase2 = true;
    const quemCuida = render().find('[data-quem-cuida]');

    expect(quemCuida.exists()).toBe(true);
    expect(quemCuida.text()).toContain('Clara');
    expect(quemCuida.text()).toContain('Maria');
  });

  it('with phase 2 off in the account keeps the robot sentence, even with ai_agents', () => {
    const wrapper = render();

    expect(wrapper.find('[data-quem-cuida]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Robô antigo');
    expect(wrapper.text()).not.toContain('Maria');
  });
});
