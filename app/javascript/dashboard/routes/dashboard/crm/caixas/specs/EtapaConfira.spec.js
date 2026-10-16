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

// #1676 — a IA de assunto em 1 funil (flag crm_avaliar_toda_mensagem da conta).
const ia = vi.hoisted(() => ({ ligada: false }));
vi.mock('../helpers/iaDeAssunto', async importOriginal => {
  const { computed } = await import('vue');
  const original = await importOriginal();
  return { ...original, useIaDeAssunto: () => computed(() => ia.ligada) };
});

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

const render = (fase2, mudar = {}) => {
  const original = formularioDaCaixa(CAIXA, fase2);
  const form = { ...formularioDaCaixa(CAIXA, fase2), ...mudar };
  return mount(EtapaConfira, {
    props: { form, original, funis: FUNIS },
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
    ia.ligada = false;
  });

  it.each([
    [false, 'chegou', 'O card nasce assim que a conversa chega.'],
    [true, 'chegou', 'O card nasce com a primeira mensagem, e a IA dá o nome.'],
    [false, 'off', 'Nada acontece sozinho: a equipe cria o card.'],
    [true, 'off', 'O sistema cria o card quando entende o assunto.'],
  ])(
    'with one pipeline and the subject AI flag %s, sums up "%s" the same way as step 3 (#1676)',
    (ligada, modo, resumo) => {
      ia.ligada = ligada;
      const wrapper = render(false, {
        modo,
        auto_create_card: modo === 'chegou',
      });

      expect(wrapper.text()).toContain(resumo);
    }
  );

  it('lists the new mode in "What changes" with the subject AI text (#1676)', () => {
    ia.ligada = true;
    const wrapper = render(false, { modo: 'off' });

    const muda = wrapper
      .findAll('li')
      .map(item => item.text())
      .join(' ');
    expect(muda).toContain('O sistema cria o card quando entende o assunto.');
    expect(muda).not.toContain('a equipe cria o card');
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
