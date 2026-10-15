import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AgentesDaCaixa from '../components/AgentesDaCaixa.vue';
import { agentesParaFormulario } from '../helpers/agentesIa';
import en from 'dashboard/i18n/locale/en/crm.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/crm.json';

const FUNIS = [
  { id: 1, name: 'Comercial' },
  { id: 2, name: 'Suporte' },
];

const agentes = ({ ultimaCaixa = true } = {}) =>
  agentesParaFormulario({
    porta: { id: 9, name: 'Clara' },
    pode_mudar: true,
    areas: [
      {
        id: 1,
        name: 'Maria',
        pipeline_ids: [1],
        parado: false,
        ultima_caixa: ultimaCaixa,
      },
    ],
    disponiveis: [{ id: 2, name: 'Marta', parado: true }],
  }).agentes;

const render = ({ podeMudar = true, lista = agentes() } = {}) => {
  let wrapper;
  wrapper = mount(AgentesDaCaixa, {
    props: {
      porta: { id: 9, name: 'Clara' },
      podeMudar,
      funis: FUNIS,
      todosOsFunis: FUNIS,
      agentes: lista,
      'onUpdate:agentes': novos => wrapper.setProps({ agentes: novos }),
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
  return wrapper;
};

describe('AgentesDaCaixa', () => {
  it('shows the inbox areas and keeps the other agents behind a button', async () => {
    const wrapper = render();

    expect(wrapper.find('[data-porta]').text()).toContain('Clara');
    expect(
      wrapper
        .findAll('[data-agente-area]')
        .map(item => item.attributes('data-agente-area'))
    ).toEqual(['Maria']);

    await wrapper.find('[data-mostrar-agentes]').trigger('click');
    expect(wrapper.findAll('[data-agente-area]')).toHaveLength(2);
  });

  it('warns that the agent stops when this is its only inbox, with undo', async () => {
    const wrapper = render();

    await wrapper.find('[data-tirar]').trigger('click');
    expect(wrapper.find('[data-sai]').text()).toContain(
      'Esta é a única caixa em que Maria trabalha. Ao salvar, Maria para de atender.'
    );
    expect(wrapper.props('agentes')[0]).toMatchObject({
      sai: true,
      pipeline_ids: [],
    });

    await wrapper.find('[data-voltar]').trigger('click');
    expect(wrapper.find('[data-sai]').exists()).toBe(false);
    expect(wrapper.props('agentes')[0]).toMatchObject({
      sai: false,
      pipeline_ids: [1],
    });
  });

  it('only says the agent leaves when it works in another inbox too', async () => {
    const wrapper = render({ lista: agentes({ ultimaCaixa: false }) });

    await wrapper.find('[data-tirar]').trigger('click');
    expect(wrapper.find('[data-sai]').text()).toContain(
      'Sai desta caixa ao salvar.'
    );
  });

  it('marking a pipeline on another agent brings it into the inbox and turns it on', async () => {
    const wrapper = render();
    await wrapper.find('[data-mostrar-agentes]').trigger('click');

    await wrapper
      .find('[data-agente-area="Marta"] [data-agente-funil="Suporte"]')
      .trigger('click');

    expect(wrapper.find('[data-agente-area="Marta"] [data-entra]').text()).toBe(
      'Entra nesta caixa e passa a atender ao salvar.'
    );
  });

  it('is read-only without permission to manage agents', () => {
    const wrapper = render({ podeMudar: false });

    expect(wrapper.find('[data-tirar]').exists()).toBe(false);
    expect(wrapper.find('[data-mostrar-agentes]').exists()).toBe(false);
    expect(
      wrapper.find('[data-agente-funil="Comercial"]').attributes('disabled')
    ).toBeDefined();
  });
});
