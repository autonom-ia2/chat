import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import LivreAlterar from '../components/LivreAlterar.vue';

// #2414 F5 — o "Salvar" só aparece pronto quando o esquema aceitaria: alvo a
// escolher e campo obrigatório preenchidos, condição com o que olhar. A ação
// avançada abre só para ver.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
  }),
}));

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

const montar = (catalogo = CATALOGO, extras = {}) =>
  mount(LivreAlterar, {
    props: {
      catalogo,
      opcoes: {
        etiqueta: [{ value: 7, label: 'vip' }],
        etiquetaPorNome: [
          { value: 'vip', label: 'vip' },
          { value: 'lead', label: 'lead' },
        ],
        ...extras,
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
  // G15 — a agente de IA é escolhida na lista da conta (só id e nome); sem
  // nenhuma, o painel diz isso em vez de abrir uma escolha vazia.
  const IA_ASSUMIR = {
    tipo: 'ia_assumir',
    grupo: 'EQUIPE',
    frase: 'IA_ASSUMIR',
    campos: [
      {
        nome: 'agente_id',
        peca: 'agente_de_ia',
        obrigatorio: true,
        rotulo: 'AGENTE_ID',
      },
    ],
  };
  const COM_IA = { ...CATALOGO, passos: [...CATALOGO.passos, IA_ASSUMIR] };
  const PASSO_IA = { id: 'g1', tipo: 'ia_assumir', agente_id: null };

  it('espera escolher a agente de IA antes de salvar', async () => {
    const wrapper = montar(COM_IA, {
      agenteDeIa: [{ value: 3, label: 'Área Suporte' }],
    });
    wrapper.vm.abrir({ tipo: 'passo', valor: PASSO_IA });
    await flushPromises();
    expect(wrapper.find('[data-peca="agente_de_ia"]').exists()).toBe(true);
    expect(salvarDesligado(wrapper)).toBe(true);

    wrapper.vm.abrir({ tipo: 'passo', valor: { ...PASSO_IA, agente_id: 3 } });
    await flushPromises();
    expect(salvarDesligado(wrapper)).toBe(false);
  });

  it('sem agente de IA na conta, diz isso e não salva', async () => {
    const wrapper = montar(COM_IA, { agenteDeIa: [] });
    wrapper.vm.abrir({ tipo: 'passo', valor: PASSO_IA });
    await flushPromises();

    expect(wrapper.find('[data-sem-agente-de-ia]').exists()).toBe(true);
    expect(salvarDesligado(wrapper)).toBe(true);
  });

  it('enquanto a lista carrega, não diz que falta agente; se não veio, diz que não carregou', async () => {
    const carregando = montar(COM_IA, { agenteDeIa: null });
    carregando.vm.abrir({ tipo: 'passo', valor: PASSO_IA });
    await flushPromises();
    expect(carregando.find('[data-sem-agente-de-ia]').exists()).toBe(false);
    expect(carregando.find('[data-agentes-de-ia-falhou]').exists()).toBe(false);

    const falhou = montar(COM_IA, { agenteDeIa: null, agenteDeIaFalhou: true });
    falhou.vm.abrir({ tipo: 'passo', valor: PASSO_IA });
    await flushPromises();
    expect(falhou.find('[data-agentes-de-ia-falhou]').exists()).toBe(true);
    expect(falhou.find('[data-sem-agente-de-ia]').exists()).toBe(false);
  });

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

  // G11: a resposta durante a espera só vale na condição do "esperar até".
  it('oferece a resposta durante a espera só na condição do "esperar até"', async () => {
    const condicao = { nome: 'condicao', peca: 'condicao', rotulo: 'CONDICAO' };
    const catalogo = {
      ...CATALOGO,
      valores: [
        { caminho: 'conversa.status', frase: 'STATUS' },
        {
          caminho: 'conversa.cliente_respondeu',
          frase: 'CLIENTE_RESPONDEU',
          so_na_espera: true,
        },
      ],
      passos: [
        { tipo: 'esperar_ate', frase: 'ESPERAR_ATE', campos: [condicao] },
        { tipo: 'se', frase: 'SE', campos: [condicao] },
      ],
    };
    const oferecidos = async tipo => {
      const wrapper = montar(catalogo);
      wrapper.vm.abrir({ tipo: 'passo', valor: { id: 'p1', tipo } });
      await flushPromises();
      return wrapper
        .findComponent({ name: 'LivreCondicao' })
        .findAllComponents({ name: 'ChoiceSelect' })[0]
        .props('options')
        .map(opcao => opcao.value);
    };

    expect(await oferecidos('esperar_ate')).toEqual([
      'conversa.status',
      'conversa.cliente_respondeu',
    ]);
    expect(await oferecidos('se')).toEqual(['conversa.status']);
  });

  // G3 (#2629): o retorno espera a escolha de pessoas e a mensagem escrita.
  it('o retorno só salva com quem recebe escolhido e a mensagem escrita', async () => {
    const catalogo = {
      ...CATALOGO,
      passos: [
        {
          tipo: 'retorno',
          frase: 'RETORNO',
          campos: [
            {
              nome: 'titulo',
              peca: 'texto',
              rotulo: 'TITULO',
              obrigatorio: true,
            },
            { nome: 'para', peca: 'quem_recebe_retorno', rotulo: 'PARA' },
            { nome: 'envio', peca: 'envio_do_retorno', rotulo: 'ENVIO' },
          ],
        },
      ],
    };
    const wrapper = montar(catalogo);
    const abrir = async extra => {
      wrapper.vm.abrir({
        tipo: 'passo',
        valor: { id: 'r1', tipo: 'retorno', titulo: ['Ligar'], ...extra },
      });
      await flushPromises();
    };

    await abrir({});
    expect(wrapper.find('[data-peca="quem_recebe_retorno"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-peca="envio_do_retorno"]').exists()).toBe(true);
    expect(salvarDesligado(wrapper)).toBe(false);

    await abrir({ para: { quem: 'pessoas', pessoas: [] } });
    expect(salvarDesligado(wrapper)).toBe(true);

    await abrir({ envio: { mensagem: [] } });
    expect(salvarDesligado(wrapper)).toBe(true);

    await abrir({ envio: { mensagem: ['Oi'] } });
    expect(salvarDesligado(wrapper)).toBe(false);
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

  // G2: a caixa do e-mail é uma escolha do ChoiceSelect, só entre as caixas de
  // e-mail da conta; sem nenhuma, o painel diz e o "Salvar" não libera.
  describe('passo "email"', () => {
    const EMAIL = {
      tipo: 'email',
      grupo: 'MENSAGEM',
      frase: 'EMAIL',
      campos: [
        {
          nome: 'caixa_id',
          peca: 'caixa_de_email',
          obrigatorio: true,
          rotulo: 'CAIXA_ID',
        },
        {
          nome: 'assunto',
          peca: 'linha_com_valores',
          obrigatorio: true,
          rotulo: 'ASSUNTO',
        },
        {
          nome: 'texto',
          peca: 'texto_com_valores',
          obrigatorio: true,
          rotulo: 'TEXTO',
        },
      ],
    };
    const passo = caixaId => ({
      id: 'p1',
      tipo: 'email',
      caixa_id: caixaId,
      assunto: ['Seu pedido'],
      texto: ['Saiu.'],
    });
    const montarEmail = caixaDeEmail =>
      mount(LivreAlterar, {
        props: {
          catalogo: { ...CATALOGO, passos: [EMAIL] },
          opcoes: { caixaDeEmail },
          atributosDaPeca: () => [],
          atributosDo: () => [],
        },
        global: {
          stubs: { SidePanel: PainelFalso, LivreTexto: true },
          mocks: { $t: chave => chave },
        },
      });

    it('escolhe entre as caixas de e-mail e só salva com uma escolhida', async () => {
      const wrapper = montarEmail([{ value: 3, label: 'Contato' }]);
      wrapper.vm.abrir({ tipo: 'passo', valor: passo(null) });
      await flushPromises();
      const escolha = wrapper
        .find('[data-peca="caixa_de_email"]')
        .findComponent({ name: 'ChoiceSelect' });
      expect(escolha.props('options')).toEqual([
        { value: 3, label: 'Contato' },
      ]);
      expect(salvarDesligado(wrapper)).toBe(true);

      await escolha.vm.$emit('update:modelValue', 3);
      expect(salvarDesligado(wrapper)).toBe(false);
      await wrapper.find('[data-salvar]').trigger('click');
      expect(wrapper.emitted('salvar')[0][0].valor.caixa_id).toBe(3);
    });

    it('o assunto é uma linha só, e cada "Pôr um dado" diz em qual caixa entra', async () => {
      const wrapper = montarEmail([{ value: 3, label: 'Contato' }]);
      wrapper.vm.abrir({ tipo: 'passo', valor: passo(3) });
      await flushPromises();
      const [assunto, texto] = wrapper.findAllComponents({
        name: 'LivreTexto',
      });

      expect(assunto.props('umaLinha')).toBe(true);
      expect(texto.props('umaLinha')).toBe(false);
      expect(assunto.props('rotuloDoDado')).toBe(
        'AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_VALOR_EM(ASSUNTO)'
      );
      expect(texto.props('rotuloDoDado')).toBe(
        'AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_VALOR_EM(TEXTO)'
      );
    });

    it('a mensagem, com um texto só, segue em caixa grande e com o rótulo de sempre', async () => {
      const MENSAGEM = {
        tipo: 'mensagem',
        grupo: 'MENSAGEM',
        frase: 'MENSAGEM',
        campos: [
          {
            nome: 'texto',
            peca: 'texto_com_valores',
            obrigatorio: true,
            rotulo: 'TEXTO',
          },
        ],
      };
      const wrapper = mount(LivreAlterar, {
        props: {
          catalogo: { ...CATALOGO, passos: [MENSAGEM] },
          opcoes: {},
          atributosDaPeca: () => [],
          atributosDo: () => [],
        },
        global: {
          stubs: { SidePanel: PainelFalso, LivreTexto: true },
          mocks: { $t: chave => chave },
        },
      });
      wrapper.vm.abrir({
        tipo: 'passo',
        valor: { id: 'm1', tipo: 'mensagem', texto: ['Oi'] },
      });
      await flushPromises();
      const texto = wrapper.findComponent({ name: 'LivreTexto' });

      expect(texto.props('umaLinha')).toBe(false);
      expect(texto.props('rotuloDoDado')).toBe('');
    });

    it('sem caixa de e-mail na conta, avisa e não salva', async () => {
      const wrapper = montarEmail([]);
      wrapper.vm.abrir({ tipo: 'passo', valor: passo(null) });
      await flushPromises();
      expect(wrapper.find('[data-sem-caixa-de-email]').exists()).toBe(true);
      expect(salvarDesligado(wrapper)).toBe(true);
    });
  });
});
