import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EtapaPessoas from '../components/EtapaPessoas.vue';
import { agentesParaFormulario } from '../helpers/agentesIa';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

const FUNIS = [{ id: 1, name: 'Comercial' }];
const PESSOAS = [
  {
    id: 5,
    name: 'Bruno Alves',
    administrator: false,
    triage: true,
    only_own: false,
    pipeline_ids: [1],
  },
];

const render = aiAgents =>
  mount(EtapaPessoas, {
    props: {
      funis: FUNIS,
      todosOsFunis: FUNIS,
      pessoas: PESSOAS,
      robo: { id: 99, name: 'Clara' },
      aiAgents,
    },
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

describe('EtapaPessoas', () => {
  it('without phase 2 keeps the sentence about the robot, as before', () => {
    const wrapper = render(null);

    expect(wrapper.find('[data-robo]').text()).toBe(
      'Clara, o agente de IA desta caixa, atende primeiro. Quando a conversa passa para uma pessoa, vale o que estiver marcado aqui.'
    );
    expect(wrapper.find('[data-agentes]').exists()).toBe(false);
  });

  it('with phase 2 lists the AI agents before the people', () => {
    const wrapper = render(
      agentesParaFormulario({
        porta: { id: 9, name: 'Clara' },
        pode_mudar: false,
        areas: [
          {
            id: 1,
            name: 'Maria',
            pipeline_ids: [1],
            parado: false,
            ultima_caixa: false,
          },
        ],
        disponiveis: [],
      })
    );

    expect(wrapper.find('[data-robo]').exists()).toBe(false);
    expect(wrapper.find('[data-porta]').text()).toContain('Clara');
    expect(wrapper.find('[data-agente-area="Maria"]').exists()).toBe(true);
    expect(wrapper.find('[data-so-leitura]').exists()).toBe(true);
  });

  it('says why the inbox takes no new area agent (#1570)', () => {
    const wrapper = render(
      agentesParaFormulario({
        porta: { id: 9, name: 'Clara' },
        pode_mudar: true,
        areas: [],
        disponiveis: [],
        recusa_area_nova: 'robo_externo',
      })
    );

    expect(wrapper.find('[data-recusa-da-caixa]').text()).toBe(
      'Esta caixa é atendida por um agente externo. Ela não recebe agente de área.'
    );
  });

  it('says nothing when the inbox takes new area agents', () => {
    const wrapper = render(
      agentesParaFormulario({
        porta: { id: 9, name: 'Clara' },
        pode_mudar: true,
        areas: [],
        disponiveis: [{ id: 2, name: 'Marta', parado: true }],
      })
    );

    expect(wrapper.find('[data-recusa-da-caixa]').exists()).toBe(false);
  });
});
