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

const montar = (catalogo = CATALOGO) =>
  mount(LivreAlterar, {
    props: {
      catalogo,
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

  // #2414 G16b: a data calculada pela metade segura o "Salvar".
  it('não salva com a data calculada pela metade', async () => {
    const wrapper = montar();
    const passo = data => ({
      id: 'p1',
      tipo: 'acao',
      acao: 'PATCH labels/:id',
      descricao: 'x',
      caminho: { id: 7 },
      corpo: { title: 'cliente', custom_attributes: { revisao: data } },
    });
    wrapper.vm.abrir({
      tipo: 'passo',
      valor: passo({
        $data: { de: 'hoje', mais: { valor: null, unidade: 'meses' } },
      }),
    });
    await flushPromises();
    expect(salvarDesligado(wrapper)).toBe(true);

    wrapper.vm.abrir({
      tipo: 'passo',
      valor: passo({
        $data: { de: 'hoje', mais: { valor: 6, unidade: 'meses' } },
      }),
    });
    await flushPromises();
    expect(salvarDesligado(wrapper)).toBe(false);
  });

  // #2414 G16b: o painel fica montado entre um passo e outro; a peça de data
  // não pode levar o modo de um para o outro.
  it('cada passo reabre a peça de data com o modo dele', async () => {
    const contato = {
      tipo: 'acao',
      nome: 'contato_alterar',
      acao: 'PATCH contacts/:id',
      grupo: 'CONTATO',
      frase: 'MUDAR_CONTATO',
      caminho: { id: { $valor: 'contato.id' } },
      fixos: {},
      campos: [
        {
          nome: 'custom_attributes',
          peca: 'atributos_do_contato',
          rotulo: 'X',
        },
      ],
    };
    const wrapper = mount(LivreAlterar, {
      props: {
        catalogo: { ...CATALOGO, passos: [contato] },
        opcoes: {},
        atributosDaPeca: () => [
          {
            attribute_key: 'revisao',
            attribute_display_name: 'Revisão',
            attribute_display_type: 'date',
          },
        ],
        atributosDo: () => [],
      },
      global: {
        stubs: { SidePanel: PainelFalso },
        mocks: { $t: chave => chave },
      },
    });
    const passo = (id, revisao) => ({
      id,
      tipo: 'acao',
      acao: 'PATCH contacts/:id',
      descricao: 'x',
      caminho: { id: { $valor: 'contato.id' } },
      corpo: { custom_attributes: { revisao } },
    });
    const modo = () =>
      wrapper.find('[data-data-modo] [role="combobox"]').text();

    wrapper.vm.abrir({
      tipo: 'passo',
      valor: passo('a', { $data: { de: 'hoje' } }),
    });
    await flushPromises();
    expect(modo()).toBe('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.HOJE');

    wrapper.vm.abrir({ tipo: 'passo', valor: passo('b', '2027-05-04') });
    await flushPromises();
    expect(modo()).toBe('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.DIA');
  });

  // #2496: o "Só se" acompanha o gatilho, e o painel diz o que entra e o que
  // sai antes do "Salvar".
  it('ao trocar o gatilho, avisa e salva o "Só se" que vale para ele', async () => {
    const recebida = {
      campo: { $valor: 'mensagem.tipo' },
      op: 'igual',
      valor: 'recebida',
    };
    const catalogo = {
      ...CATALOGO,
      gatilhos: [
        { tipo: 'conversa.resolvida', frase: 'RESOLVIDA' },
        {
          tipo: 'mensagem.criada',
          frase: 'MENSAGEM',
          filtro_sugerido: recebida,
        },
      ],
      valores: [
        ...CATALOGO.valores,
        {
          caminho: 'mensagem.tipo',
          frase: 'TIPO',
          so_no_gatilho: 'mensagem.criada',
        },
      ],
    };
    const wrapper = montar(catalogo);
    const escolherGatilho = async tipo => {
      await wrapper
        .findComponent({ name: 'ChoiceSelect' })
        .vm.$emit('update:modelValue', tipo);
      await flushPromises();
    };

    wrapper.vm.abrir({ tipo: 'gatilho', valor: null });
    await flushPromises();
    await escolherGatilho('mensagem.criada');
    expect(wrapper.find('[data-filtro-entra]').exists()).toBe(true);
    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar')[0][0].valor).toEqual({
      tipo: 'mensagem.criada',
      filtros: [recebida],
    });

    wrapper.vm.abrir({
      tipo: 'gatilho',
      valor: { tipo: 'mensagem.criada', filtros: [recebida] },
    });
    await flushPromises();
    await escolherGatilho('conversa.resolvida');
    expect(wrapper.find('[data-filtro-entra]').exists()).toBe(false);
    expect(wrapper.findAll('[data-filtro-sai]')).toHaveLength(1);
    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar')[1][0].valor).toEqual({
      tipo: 'conversa.resolvida',
      filtros: [],
    });
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
