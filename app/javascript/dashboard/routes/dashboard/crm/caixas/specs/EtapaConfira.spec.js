import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EtapaConfira from '../components/EtapaConfira.vue';
import { formularioDaCaixa } from '../helpers/agentesIa';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

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
