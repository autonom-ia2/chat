import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CaixaCartao from '../components/CaixaCartao.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1570 — "Quem cuida" mostra os agentes de IA só com a Fase 2 dos Agentes
// ligada no payload da conta (`autonomia_agents_fase2`), a mesma fonte da tela
// dos Agentes; a caixa trazer `ai_agents` não basta.
const conta = vi.hoisted(() => ({ fase2: false, porCaixa: false, ia: false }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    'accounts/getAccount': () => () => ({
      autonomia_agents_fase2: conta.fase2,
      autonomia_agente_ia_por_caixa: conta.porCaixa,
      features: { crm_avaliar_toda_mensagem: conta.ia },
    }),
    getCurrentAccountId: () => 1,
    'inboxes/getInboxById': () => () => ({}),
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

const render = (caixa = CAIXA) =>
  mount(CaixaCartao, {
    props: { caixa, funis: FUNIS },
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
    conta.porCaixa = false;
    conta.ia = false;
  });

  // O cartão diz o que a caixa faz hoje: vale a IA de assunto gravada, não a
  // flag (caixa de antes da flag segue sem a IA até ser salva ou virada).
  it.each([
    ['off', true, 'O card nasce assim que a conversa chega.'],
    ['auto', true, 'O card nasce com a primeira mensagem, e a IA dá o nome.'],
    ['off', false, 'Nada acontece sozinho: a equipe cria o card.'],
    ['auto', false, 'O sistema cria um card para cada pedido do cliente.'],
  ])(
    'one pipeline, saved subject AI %s, card on arrival %s: says what the system does (#1676)',
    (modo, chegou, frase) => {
      conta.ia = true;
      const caixa = {
        ...CAIXA,
        subject_ai_mode: modo,
        auto_create_card: chegou,
      };

      expect(render(caixa).text()).toContain(frase);
    }
  );

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

  it('says when the first to answer is an external agent (#1570)', () => {
    const wrapper = render({
      ...CAIXA,
      agent_bot: { id: 99, name: 'Robô antigo', tipo_do_principal: 'externo' },
    });

    expect(wrapper.text()).toContain(
      'Robô antigo (agente externo) atende primeiro'
    );
  });

  it('with phase 2 on, an external agent is never shown as the AI door (#1570)', () => {
    conta.fase2 = true;
    const quemCuida = render({
      ...CAIXA,
      agent_bot: { id: 99, name: 'Robô n8n', tipo_do_principal: 'externo' },
      ai_agents: { ...CAIXA.ai_agents, porta: null },
    }).find('[data-quem-cuida]');

    expect(quemCuida.find('[data-externo]').text()).toBe(
      'Robô n8n (agente externo) atende primeiro'
    );
    expect(quemCuida.text()).not.toContain('Robô n8n atende primeiro');
  });
  it('with the AI agent tab per inbox on, calls the agent from another system an AI agent (#1648)', () => {
    conta.porCaixa = true;
    const wrapper = render({
      ...CAIXA,
      agent_bot: { id: 99, name: 'Robô antigo', tipo_do_principal: 'externo' },
    });

    expect(wrapper.text()).toContain(
      'Robô antigo (agente de IA) atende primeiro'
    );
    conta.porCaixa = false;
  });
});
