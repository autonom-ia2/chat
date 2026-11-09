import { flushPromises, mount } from '@vue/test-utils';
import LivreGatilho from '../components/LivreGatilho.vue';
import LivreAlterar from '../components/LivreAlterar.vue';
import { fraseDoGatilho } from '../frases';

// #2709 — o lembrete antes da reunião: quanto tempo antes (número e unidade) e,
// opcional, a página de agendamento.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave,
  }),
}));

const t = (chave, valores = {}) => [chave, ...Object.values(valores)].join(' ');
const LEMBRETE = {
  tipo: 'card.antes_da_reuniao',
  alvo: 'Crm::Card',
  frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_ANTES_DA_REUNIAO',
  grupo: 'reuniao',
  parametros: [
    {
      nome: 'antes',
      peca: 'antes',
      obrigatorio: true,
      frase: 'AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.ANTES',
    },
    {
      nome: 'pagina_id',
      peca: 'pagina',
      obrigatorio: false,
      frase: 'AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.PAGINA_ID',
    },
  ],
};
const CATALOGO = {
  gatilhos: [LEMBRETE],
  alvos: { 'Crm::Card': ['card', 'conversa', 'contato', 'reuniao'] },
  operadores: [],
  unidades: [],
  valores: [],
  passos: [],
};

const PainelFalso = {
  name: 'SidePanel',
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /><slot name="footer" /></div>',
};

describe('#2709 — lembrete antes da reunião', () => {
  it('a frase diz quanto tempo antes; com a página, diz a página', () => {
    const gatilho = {
      tipo: 'card.antes_da_reuniao',
      antes: { valor: 1, unidade: 'dias' },
    };
    expect(fraseDoGatilho(gatilho, CATALOGO, t)).toBe(
      'AUTOMACAO_LIVRE.GATILHO_COM.CARD_ANTES_DA_REUNIAO AUTOMACAO_LIVRE.FRASES.DURACAO 1 AUTOMACAO_LIVRE.UNIDADES.DIAS'
    );
    expect(
      fraseDoGatilho({ ...gatilho, pagina_id: 7 }, CATALOGO, t, {
        pagina: { 7: 'Entrevistas' },
      })
    ).toContain('AUTOMACAO_LIVRE.GATILHO_NA_PAGINA');
  });

  it('escolher o lembrete já vem com 1 dia antes e o aviso de como confere', async () => {
    const wrapper = mount(LivreGatilho, {
      props: { modelValue: null, gatilhos: [LEMBRETE] },
      global: { mocks: { $t: chave => chave } },
    });
    wrapper
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', 'card.antes_da_reuniao');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { tipo: 'card.antes_da_reuniao', antes: { valor: 1, unidade: 'dias' } },
    ]);

    await wrapper.setProps({
      modelValue: wrapper.emitted('update:modelValue').at(-1)[0],
    });
    expect(wrapper.find('[data-antes]').exists()).toBe(true);
    expect(wrapper.find('[data-aviso-tempo]').text()).toBe(
      'AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.AVISO_LEMBRETE'
    );
    wrapper
      .findComponent({ name: 'LivreDuracao' })
      .vm.$emit('update:modelValue', { valor: 3, unidade: 'horas' });
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { tipo: 'card.antes_da_reuniao', antes: { valor: 3, unidade: 'horas' } },
    ]);
  });

  it('sem o número, o "Salvar" fica parado', async () => {
    const wrapper = mount(LivreAlterar, {
      props: {
        catalogo: CATALOGO,
        opcoes: {},
        atributosDaPeca: () => [],
        atributosDo: () => [],
        gatilhos: [LEMBRETE],
        escolhasDoGatilho: {},
      },
      global: {
        stubs: { SidePanel: PainelFalso },
        mocks: { $t: chave => chave },
      },
    });
    wrapper.vm.abrir({
      tipo: 'gatilho',
      valor: {
        tipo: 'card.antes_da_reuniao',
        antes: { valor: null, unidade: 'dias' },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-salvar]').attributes('disabled')).toBeDefined();

    wrapper
      .findComponent({ name: 'LivreDuracao' })
      .vm.$emit('update:modelValue', { valor: 2, unidade: 'dias' });
    await flushPromises();
    expect(
      wrapper.find('[data-salvar]').attributes('disabled')
    ).toBeUndefined();
  });
});
