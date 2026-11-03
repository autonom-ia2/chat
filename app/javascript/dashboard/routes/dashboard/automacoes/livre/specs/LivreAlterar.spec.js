import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import LivreAlterar from '../components/LivreAlterar.vue';

// #2414 F5 — o "Salvar" só aparece pronto quando o esquema aceitaria: alvo a
// escolher e campo obrigatório preenchidos, condição com o que olhar. A ação
// avançada abre só para ver.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const PainelFalso = defineComponent({
  name: 'SidePanel',
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /><slot name="footer" /></div>',
});

const ETIQUETA_ALTERAR = {
  tipo: 'acao',
  nome: 'etiqueta_alterar',
  acao: 'PATCH labels/:id',
  grupo: 'ETIQUETA',
  frase: 'MUDAR_ETIQUETA',
  caminho: { id: { escolher: 'etiqueta', rotulo: 'QUAL' } },
  fixos: {},
  campos: [{ nome: 'title', peca: 'texto', rotulo: 'NOME', obrigatorio: true }],
};
const CONVERSA_ETIQUETAS = {
  tipo: 'acao',
  nome: 'conversa_etiquetas',
  acao: 'PATCH conversations/:conversation_id/labels/alterar',
  grupo: 'CONVERSA',
  frase: 'ETIQUETAS',
  caminho: { conversation_id: { $valor: 'conversa.id' } },
  fixos: {},
  campos: [
    { nome: 'por', peca: 'etiquetas', rotulo: 'POR' },
    { nome: 'tirar', peca: 'etiquetas', rotulo: 'TIRAR' },
  ],
};
const CATALOGO = {
  gatilhos: [],
  operadores: [{ op: 'vazio', pede_valor: false, frase: 'VAZIO' }],
  unidades: [],
  valores: [{ caminho: 'conversa.status', frase: 'STATUS' }],
  passos: [ETIQUETA_ALTERAR, CONVERSA_ETIQUETAS],
};

const montar = () =>
  mount(LivreAlterar, {
    props: {
      catalogo: CATALOGO,
      opcoes: {
        etiqueta: [{ value: 7, label: 'vip' }],
        etiquetaPorNome: [
          { value: 'vip', label: 'vip' },
          { value: 'lead', label: 'lead' },
        ],
      },
      atributosDaPeca: () => [],
      atributosDo: () => [],
    },
    global: {
      stubs: { SidePanel: PainelFalso },
      mocks: { $t: chave => chave },
    },
  });

const salvarDesligado = wrapper =>
  wrapper.find('[data-salvar]').attributes('disabled') !== undefined;

describe('LivreAlterar', () => {
  it('espera o alvo e o campo obrigatório antes de salvar', async () => {
    const wrapper = montar();
    const passo = {
      id: 'p1',
      tipo: 'acao',
      acao: 'PATCH labels/:id',
      descricao: 'x',
      caminho: {},
      corpo: {},
    };
    wrapper.vm.abrir({ tipo: 'passo', valor: passo });
    await flushPromises();
    expect(salvarDesligado(wrapper)).toBe(true);

    wrapper.vm.abrir({
      tipo: 'passo',
      valor: { ...passo, caminho: { id: 7 }, corpo: { title: 'cliente' } },
    });
    await flushPromises();
    expect(salvarDesligado(wrapper)).toBe(false);

    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar')[0][0].valor.caminho).toEqual({ id: 7 });
  });

  it('não salva condição sem o que olhar', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({
      tipo: 'condicao',
      indice: -1,
      valor: { campo: { $valor: '' }, op: 'vazio' },
    });
    await flushPromises();
    expect(salvarDesligado(wrapper)).toBe(true);
  });

  it('etiqueta marcada em "Pôr" fica bloqueada em "Tirar"', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({
      tipo: 'passo',
      valor: {
        id: 'p1',
        tipo: 'acao',
        acao: 'PATCH conversations/:conversation_id/labels/alterar',
        descricao: 'x',
        caminho: { conversation_id: { $valor: 'conversa.id' } },
        corpo: { por: ['vip'] },
      },
    });
    await flushPromises();
    const botao = (campo, nome) =>
      wrapper
        .findAll(`[data-campo="${campo}"] button`)
        .find(item => item.text() === nome);

    expect(botao('tirar', 'vip').attributes('aria-disabled')).toBe('true');
    expect(botao('tirar', 'lead').attributes('aria-disabled')).toBeUndefined();
    expect(botao('por', 'vip').attributes('aria-disabled')).toBeUndefined();

    await botao('tirar', 'vip').trigger('click');
    await botao('tirar', 'lead').trigger('click');
    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar')[0][0].valor.corpo).toEqual({
      por: ['vip'],
      tirar: ['lead'],
    });
  });

  it('a ação avançada abre só para ver, e dá para tirar', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({
      tipo: 'passo',
      valor: {
        id: 'p9',
        tipo: 'acao',
        acao: 'PUT labels/:id',
        descricao: 'Guia',
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-salvar]').exists()).toBe(false);
    expect(wrapper.find('[data-avancada-dica]').exists()).toBe(true);
    await wrapper.find('[data-tirar]').trigger('click');
    expect(wrapper.emitted('tirar')).toHaveLength(1);
  });
});
