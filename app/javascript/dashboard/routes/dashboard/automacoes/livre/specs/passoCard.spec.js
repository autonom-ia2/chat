import { defineComponent } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import LivreAlterar from '../components/LivreAlterar.vue';
import LivreSeletorPasso from '../components/LivreSeletorPasso.vue';
import { novoPasso } from '../catalogo';

// #2414 G4 — o passo "criar card" no editor: nasce sem etapa, a etapa é
// escolhida agrupada pelo funil (sem <select> nativo) e o "Salvar" espera por
// ela; o seletor só oferece o passo a quem pode mexer no funil.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
const permissao = vi.hoisted(() => ({ funil: true }));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({
        canManagePipelines: computed(() => permissao.funil),
      }),
    };
  }
);

const PainelFalso = defineComponent({
  name: 'SidePanel',
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /><slot name="footer" /></div>',
});

const CARD = {
  tipo: 'card',
  grupo: 'FUNIL',
  requer: 'automacao_gatilhos',
  funil: true,
  frase: 'AUTOMACAO_LIVRE.PASSOS.CARD',
  campos: [
    {
      nome: 'etapa_id',
      peca: 'etapa',
      obrigatorio: true,
      rotulo: 'AUTOMACAO_LIVRE.CAMPOS.ETAPA_ID',
    },
  ],
};
const CATALOGO = {
  gatilhos: [],
  operadores: [],
  unidades: [],
  valores: [],
  grupos: [{ chave: 'FUNIL', frase: 'AUTOMACAO_LIVRE.GRUPOS.FUNIL' }],
  passos: [CARD],
};
const ETAPAS = [
  { label: 'Melhorias', options: [{ value: 12, label: 'Para tratar' }] },
];

const global = {
  stubs: { SidePanel: PainelFalso },
  mocks: { $t: chave => chave },
};

describe('passo "criar card" (G4)', () => {
  beforeEach(() => {
    permissao.funil = true;
  });

  it('nasce sem etapa', () => {
    expect(novoPasso(CARD, 'p1', chave => chave)).toEqual({
      id: 'p1',
      tipo: 'card',
      etapa_id: null,
    });
  });

  it('escolhe a etapa agrupada pelo funil e só salva com ela', async () => {
    const wrapper = mount(LivreAlterar, {
      props: {
        catalogo: CATALOGO,
        opcoes: {},
        atributosDaPeca: () => [],
        atributosDo: () => [],
        escolhasDoGatilho: { etapas: ETAPAS },
      },
      global,
    });
    wrapper.vm.abrir({
      tipo: 'passo',
      novo: true,
      valor: { id: 'p1', tipo: 'card', etapa_id: null },
    });
    await flushPromises();

    const peca = wrapper.find('[data-peca="etapa"]');
    expect(peca.exists()).toBe(true);
    expect(wrapper.find('select').exists()).toBe(false);
    const escolha = peca.findComponent({ name: 'ChoiceSelect' });
    expect(escolha.props('groups')).toEqual(ETAPAS);
    expect(wrapper.find('[data-salvar]').attributes('disabled')).toBeDefined();

    await escolha.vm.$emit('update:modelValue', 12);
    await flushPromises();
    expect(
      wrapper.find('[data-salvar]').attributes('disabled')
    ).toBeUndefined();
    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar')[0][0].valor).toEqual({
      id: 'p1',
      tipo: 'card',
      etapa_id: 12,
    });
  });

  it('o seletor só oferece o passo a quem pode mexer no funil', () => {
    const montar = () =>
      mount(LivreSeletorPasso, {
        props: { catalogo: CATALOGO, liberado: () => true },
        global,
      });
    expect(montar().text()).toContain('AUTOMACAO_LIVRE.PASSOS.CARD');

    permissao.funil = false;
    expect(montar().text()).not.toContain('AUTOMACAO_LIVRE.PASSOS.CARD');
  });
});
