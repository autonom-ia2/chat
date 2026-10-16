import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EtapaConfira from '../components/EtapaConfira.vue';
import { formularioDaCaixa } from '../helpers/agentesIa';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

// #1648 — a aba "Agente de IA" por caixa da conta (desligada: como a main).
const porCaixa = vi.hoisted(() => ({ ligada: false }));
vi.mock(
  'dashboard/routes/dashboard/autonomia/agentes/composables/useAgenteIaPorCaixa',
  async () => {
    const { computed } = await import('vue');
    return { useAgenteIaPorCaixa: () => computed(() => porCaixa.ligada) };
  }
);

// #1570 — a conferência diz "agente externo" quando quem atende primeiro é
// robô de outro sistema, com ou sem a Fase 2, e nunca o mostra como porta.
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
  agent_bot: { id: 99, name: 'Robô n8n', tipo_do_principal: 'externo' },
  people: [],
  ai_agents: { porta: null, pode_mudar: false, areas: [], disponiveis: [] },
};

const render = fase2 => {
  const form = formularioDaCaixa(CAIXA, fase2);
  return mount(EtapaConfira, {
    props: { form, original: form, funis: FUNIS },
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
};

describe('EtapaConfira', () => {
  beforeEach(() => {
    porCaixa.ligada = false;
  });

  it('with the AI agent tab per inbox on, calls the agent from another system an AI agent (#1648)', () => {
    porCaixa.ligada = true;
    const wrapper = render(true);

    expect(wrapper.find('[data-robo]').text()).toBe(
      'Primeiro atende Robô n8n, o agente de IA. Depois, as pessoas abaixo.'
    );
  });

  it.each([
    ['off', false],
    ['on', true],
  ])(
    'with phase 2 %s says the external agent answers first (#1570)',
    (_, fase2) => {
      const wrapper = render(fase2);

      expect(wrapper.find('[data-robo]').text()).toBe(
        'Primeiro atende Robô n8n, o agente externo. Depois, as pessoas abaixo.'
      );
      expect(wrapper.text()).not.toContain(
        'Atende primeiro todas as conversas desta caixa.'
      );
    }
  );
});

// #1140 (correção 1) — quem recebe cada assunto é a resposta do servidor (a
// regra do motor de entrega). Quem marcou o assunto mas só vê as dele aparece
// fora da fila, e o assunto sem ninguém ganha um aviso.
describe('EtapaConfira: quem recebe', () => {
  const DOIS_FUNIS = [
    { id: 1, name: 'Vendas', stages: [{ id: 11, name: 'Novo' }] },
    { id: 2, name: 'Pós-venda', stages: [{ id: 21, name: 'Aberto' }] },
  ];
  const PESSOAS = [
    {
      id: 5,
      name: 'Ana Ribeiro',
      administrator: false,
      triage: true,
      all_pipelines: false,
      pipeline_ids: [1],
      only_own: false,
    },
    {
      id: 6,
      name: 'Bruno Lima',
      administrator: false,
      triage: false,
      all_pipelines: false,
      pipeline_ids: [2],
      only_own: true,
    },
  ];
  const montar = props => {
    const form = formularioDaCaixa(
      {
        ...CAIXA,
        pipeline_ids: [1, 2],
        subject_ai_mode: 'off',
        auto_create_card: false,
        agent_bot: null,
        people: PESSOAS,
      },
      false
    );
    return mount(EtapaConfira, {
      props: { form, original: form, funis: DOIS_FUNIS, ...props },
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
  };

  it('shows only who the server says receives, and Bruno as "só vê as dele"', () => {
    const wrapper = montar({
      quemRecebe: { triagem: [5], funis: { 1: [5], 2: [] } },
    });

    const linhas = wrapper.findAll('li').map(li => li.text());
    expect(linhas.find(linha => linha.startsWith('Vendas'))).toContain(
      'Vendas:Ana'
    );
    const pos = linhas.find(linha => linha.startsWith('Pós-venda'));
    expect(pos).toContain('ninguém ainda');
    expect(pos.startsWith('Pós-venda:ninguém ainda')).toBe(true);
    expect(wrapper.find('[data-rodizio-fora]').text()).toBe(
      'Bruno só vê as dele, não recebe.'
    );
    expect(wrapper.find('[data-ninguem-recebe]').text()).toBe(
      'Ninguém pode receber as conversas de Pós-venda. Elas esperam até alguém passar a cuidar do assunto.'
    );
  });

  it('has no warning when every subject has someone', () => {
    const wrapper = montar({
      quemRecebe: { triagem: [5], funis: { 1: [5], 2: [5] } },
    });

    expect(wrapper.find('[data-ninguem-recebe]').exists()).toBe(false);
  });

  it('says it is checking while the server has not answered', () => {
    const wrapper = montar({ quemRecebe: null });

    expect(wrapper.text()).toContain('Conferindo quem recebe…');
    expect(wrapper.find('[data-ninguem-recebe]').exists()).toBe(false);
  });

  it('offers to try again when the server fails', async () => {
    const wrapper = montar({ quemRecebe: null, quemRecebeErro: true });

    expect(wrapper.text()).toContain(
      'Não deu para conferir quem recebe agora.'
    );
    await wrapper.get('[role="alert"] button').trigger('click');
    expect(wrapper.emitted('conferirDeNovo')).toHaveLength(1);
  });
});
