import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { onBeforeRouteLeave, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import LivreEditorPage from '../pages/LivreEditorPage.vue';
import LivreConfira from '../components/LivreConfira.vue';
import { useCatalogo } from '../catalogo';

// #2414 F5 — o editor: a nova fica na tela até guardar ou ligar; a salva junta
// as mudanças até "Salvar tudo" (#2486), levando a versão vista; 409 mantém o
// rascunho até "Ver a versão nova"; 422 mostra o que corrigir; o passo
// avançado volta idêntico.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (chave, valores) => (valores ? `${chave}` : chave) }),
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({
    name: 'automacoes_livre_editar',
    params: { accountId: 1, id: 5 },
    query: {},
  });
  const router = {
    push: vi.fn(),
    replace: vi.fn(destino => {
      if (destino.name) rota.name = destino.name;
      if (destino.params) rota.params = destino.params;
      rota.query = destino.query || {};
    }),
  };
  const guardas = [];
  return {
    useRoute: () => rota,
    useRouter: () => router,
    onBeforeRouteLeave: vi.fn(guarda => guardas.push(guarda)),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// As flags da conta: a receita que pede mensagem só abre com ela ligada.
const flags = vi.hoisted(() => new Set(['automacao_mensagens']));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: flag => flags.has(flag) }),
}));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: criarRef } = await import('vue');
  const podeMudar = criarRef(true);
  // G32: o filtro de página dos gatilhos de reunião pede o agendamento.
  return {
    useCanManage: () => podeMudar,
    usePermissionGranted: () => podeMudar,
  };
});
vi.mock('dashboard/composables/store', async () => {
  const { ref: criarRef } = await import('vue');
  return {
    useStore: () => ({ dispatch: vi.fn() }),
    useMapGetter: getter => {
      if (getter === 'getCurrentUserID') return criarRef(7);
      if (getter === 'attributes/getAttributesByModel')
        return criarRef(() => []);
      return criarRef([]);
    },
  };
});
// #2597: quem lê o valor do card. O espelho tem spec próprio
// (valorProtegido.spec.js); aqui só a ligação com o catálogo do Alterar.
const leValores = vi.hoisted(() => ({ sim: true }));
vi.mock('../usePodeLerValor', async () => {
  const { ref: criarRef } = await import('vue');
  return { usePodeLerValor: () => criarRef(() => leValores.sim) };
});
// #2499: os gatilhos de card pedem a chave de funis; as etapas vêm do CRM.
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { ref: criarRef } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: criarRef(true) }),
    };
  }
);
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: vi.fn(() =>
      Promise.resolve({ data: { payload: [{ id: 3, name: 'Vendas' }] } })
    ),
    getStages: vi.fn(() =>
      Promise.resolve({ data: { payload: [{ id: 12, name: 'Orçamento' }] } })
    ),
  },
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: {
    passos: vi.fn(),
    show: vi.fn(),
    salvar: vi.fn(),
    create: vi.fn(),
    ligar: vi.fn(),
    desligar: vi.fn(),
    renomear: vi.fn(),
    historico: vi.fn(() =>
      Promise.resolve({
        data: { execucoes: [], versoes: {}, pagina: 1, mais: false },
      })
    ),
  },
}));

const CATALOGO = {
  gatilhos: [{ tipo: 'conversa.criada', frase: 'G' }],
  operadores: [],
  unidades: [{ valor: 'dias', frase: 'DIAS' }],
  valores: [],
  grupos: [{ chave: 'CONTROLE', frase: 'CONTROLE' }],
  passos: [
    {
      tipo: 'esperar',
      grupo: 'CONTROLE',
      frase: 'ESPERAR',
      campos: [{ nome: 'duracao', peca: 'duracao' }],
    },
    { tipo: 'parar', grupo: 'CONTROLE', frase: 'PARAR', campos: [] },
  ],
  receitas: [
    {
      chave: 'AGRADECER',
      frase: 'TITULO',
      requer: ['automacao_mensagens'],
      receita: {
        gatilho: { tipo: 'conversa.resolvida' },
        passos: [{ id: 'p1', tipo: 'mensagem', texto: ['Obrigado'] }],
      },
    },
  ],
};

const AVANCADO = {
  id: 'p2',
  tipo: 'acao',
  acao: 'PUT labels/:id',
  descricao: 'Trocar a etiqueta inteira',
  caminho: { id: 7 },
  corpo: { title: 'vip' },
};

const salva = (extra = {}) => ({
  id: 5,
  nome: 'Boas-vindas',
  ativa: false,
  versao: {
    id: 11,
    numero: 2,
    receita: {
      gatilho: { tipo: 'conversa.criada' },
      passos: [
        { id: 'p1', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
        AVANCADO,
      ],
    },
  },
  ...extra,
});

// Os painéis de verdade usam o SidePanel; aqui guardam o que abriram. Os falsos
// são objetos simples: um arquivo de spec não define componente (one-component-per-file).
const abertos = [];
const AlterarFalso = {
  name: 'LivreAlterar',
  props: { catalogo: { type: Object, default: null } },
  setup(_, { expose }) {
    expose({ abrir: item => abertos.push(item), fechar: vi.fn() });
  },
  template: '<div data-alterar-falso />',
};
const SeletorFalso = {
  name: 'LivreSeletorPasso',
  setup(_, { expose }) {
    const aberto = ref(false);
    expose({
      open: () => {
        aberto.value = true;
      },
      close: () => {
        aberto.value = false;
      },
    });
    return { aberto };
  },
  template: '<div data-seletor-falso :data-aberto="aberto" />',
};

const dialogo = { abrir: vi.fn() };
const DialogoFalso = {
  name: 'DialogoDaCasa',
  setup(_, { expose }) {
    expose({ abrir: () => dialogo.abrir() });
  },
  template: '<div data-dialogo-falso />',
};

const montar = () =>
  mount(LivreEditorPage, {
    global: {
      stubs: {
        LivreAlterar: AlterarFalso,
        LivreSeletorPasso: SeletorFalso,
        DialogoDaCasa: DialogoFalso,
      },
      mocks: { $t: chave => chave },
    },
  });

const rota = useRoute();
const respostaDeErro = (status, data = {}) =>
  Object.assign(new Error('falhou'), { response: { status, data } });

// A rota é a mesma para todas as montagens: a de um teste não pode ouvir a do
// próximo.
enableAutoUnmount(afterEach);

describe('LivreEditorPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    abertos.length = 0;
    leValores.sim = true;
    rota.name = 'automacoes_livre_editar';
    rota.params = { accountId: 1, id: 5 };
    rota.query = {};
    AutomacoesAPI.passos.mockResolvedValue({ data: CATALOGO });
    AutomacoesAPI.show.mockResolvedValue({ data: salva() });
  });

  // Ligada, o aviso diz o que o salvar faz: vale na hora para quem ligou (7),
  // pausa quando é outra pessoa.
  it.each([
    ['desligada', { ativa: false }, null],
    ['ligada por mim', { ativa: true, ligada_por: { id: 7 } }, 'LIGADA_AVISO'],
    [
      'ligada por outra pessoa',
      { ativa: true, ligada_por: { id: 8 } },
      'LIGADA_POR_OUTRA',
    ],
  ])('%s: aviso no topo', async (_caso, extra, chave) => {
    AutomacoesAPI.show.mockResolvedValue({ data: salva(extra) });
    const wrapper = montar();
    await flushPromises();

    const aviso = wrapper.find('[data-ligada]');
    expect(aviso.exists()).toBe(Boolean(chave));
    if (chave) expect(aviso.text()).toBe(`AUTOMACAO_LIVRE.EDITOR.${chave}`);
  });

  // Abre o passo p1 e salva no painel com outra duração: só a tela muda.
  const trocarDuracao = async (wrapper, valor) => {
    wrapper.findComponent(LivreConfira).vm.$emit('alterar', 'p1');
    await flushPromises();
    wrapper.findComponent(AlterarFalso).vm.$emit('salvar', {
      tipo: 'passo',
      valor: { ...abertos.at(-1).valor, duracao: { valor, unidade: 'dias' } },
    });
    await flushPromises();
  };
  const duracaoNaTela = wrapper =>
    wrapper.findComponent(LivreConfira).props('receita').passos[0].duracao
      .valor;

  // #2486: ligada ou desligada, a regra é uma só.
  it.each([
    ['desligada', { ativa: false }],
    ['ligada', { ativa: true, ligada_por: { id: 7 } }],
  ])(
    '%s: junta as mudanças na tela e salva tudo numa versão só, sobre a versão vista',
    async (_caso, extra) => {
      AutomacoesAPI.show.mockResolvedValue({ data: salva(extra) });
      AutomacoesAPI.salvar.mockImplementation(async (_id, { receita }) => ({
        data: salva({ ...extra, versao: { id: 12, numero: 3, receita } }),
      }));
      const wrapper = montar();
      await flushPromises();
      expect(wrapper.find('[data-rascunho]').exists()).toBe(false);

      await trocarDuracao(wrapper, 3);
      await trocarDuracao(wrapper, 5);

      expect(AutomacoesAPI.salvar).not.toHaveBeenCalled();
      expect(wrapper.find('[data-rascunho]').exists()).toBe(true);
      await wrapper.find('[data-salvar-tudo]').trigger('click');
      await flushPromises();

      expect(AutomacoesAPI.salvar).toHaveBeenCalledTimes(1);
      const [id, { receita, baseVersaoId }] =
        AutomacoesAPI.salvar.mock.calls[0];
      expect(id).toBe(5);
      expect(baseVersaoId).toBe(11);
      expect(receita.passos[0].duracao.valor).toBe(5);
      expect(receita.passos[1]).toEqual(AVANCADO);
      expect(useAlert).toHaveBeenCalledWith('AUTOMACAO_LIVRE.EDITOR.SALVOU');
      expect(wrapper.find('[data-rascunho]').exists()).toBe(false);
    }
  );

  it('abrir e salvar sem mudar nada não vira rascunho', async () => {
    const wrapper = montar();
    await flushPromises();

    await trocarDuracao(wrapper, 1);

    expect(wrapper.find('[data-rascunho]').exists()).toBe(false);
  });

  it('Descartar volta para a versão salva', async () => {
    const wrapper = montar();
    await flushPromises();
    await trocarDuracao(wrapper, 3);

    await wrapper.find('[data-descartar]').trigger('click');
    await flushPromises();

    expect(duracaoNaTela(wrapper)).toBe(1);
    expect(wrapper.find('[data-rascunho]').exists()).toBe(false);
    expect(AutomacoesAPI.salvar).not.toHaveBeenCalled();
  });

  it('409: o rascunho fica na tela com o aviso, e só "Ver a versão nova" recarrega', async () => {
    AutomacoesAPI.salvar.mockRejectedValue(respostaDeErro(409));
    const wrapper = montar();
    await flushPromises();
    await trocarDuracao(wrapper, 3);

    await wrapper.find('[data-salvar-tudo]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-conflito]').text()).toContain(
      'AUTOMACAO_LIVRE.EDITOR.CONFLITO'
    );
    expect(duracaoNaTela(wrapper)).toBe(3);
    expect(AutomacoesAPI.show).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-ligar]').attributes('disabled')).toBeDefined();

    await wrapper.find('[data-ver-nova]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.show).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-conflito]').exists()).toBe(false);
    expect(duracaoNaTela(wrapper)).toBe(1);
  });

  it('409 sem rascunho diz que alguém mudou, e Desligar segue funcionando', async () => {
    AutomacoesAPI.ligar.mockRejectedValue(respostaDeErro(409));
    AutomacoesAPI.desligar.mockResolvedValue({ data: { ativa: false } });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-ligar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-conflito]').text()).toContain(
      'AUTOMACAO_LIVRE.MUDOU'
    );
    expect(wrapper.find('[data-ligar]').attributes('disabled')).toBeDefined();
  });

  it('com rascunho, recarregar ou fechar a aba pede confirmação', async () => {
    const wrapper = montar();
    await flushPromises();
    const fechar = () => {
      const evento = new Event('beforeunload', { cancelable: true });
      window.dispatchEvent(evento);
      return evento.defaultPrevented;
    };
    expect(fechar()).toBe(false);

    await trocarDuracao(wrapper, 3);

    expect(fechar()).toBe(true);
  });

  // Qualidade 🟠 (#2495): o nome sai no blur, junto com o clique em "Salvar
  // tudo"; ele não pode liberar a tela no meio do salvar nem trazer a versão
  // antiga de volta.
  const adiado = () => {
    let resolver;
    const promessa = new Promise(ok => {
      resolver = ok;
    });
    return { promessa, resolver };
  };
  const renomearESalvar = async (wrapper, ordem) => {
    const nomeVolta = adiado();
    const salvarVolta = adiado();
    AutomacoesAPI.renomear.mockReturnValue(nomeVolta.promessa);
    AutomacoesAPI.salvar.mockReturnValue(salvarVolta.promessa);
    await trocarDuracao(wrapper, 3);
    await wrapper.find('[data-nome] input').setValue('Outro nome');
    await wrapper.find('[data-nome] input').trigger('blur');
    await wrapper.find('[data-salvar-tudo]').trigger('click');
    const respostas = {
      nome: () => nomeVolta.resolver({ data: salva({ nome: 'Outro nome' }) }),
      salvar: () =>
        salvarVolta.resolver({
          data: salva({
            versao: {
              id: 12,
              numero: 3,
              receita: AutomacoesAPI.salvar.mock.calls[0][1].receita,
            },
          }),
        }),
    };
    const [primeiro, segundo] = ordem;
    respostas[primeiro]();
    await flushPromises();
    const botao = wrapper.find('[data-salvar-tudo]');
    if (botao.exists()) await botao.trigger('click');
    respostas[segundo]();
    await flushPromises();
  };

  it('nome que volta antes do salvar não libera um 2º Salvar tudo', async () => {
    const wrapper = montar();
    await flushPromises();

    await renomearESalvar(wrapper, ['nome', 'salvar']);

    expect(AutomacoesAPI.salvar).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-conflito]').exists()).toBe(false);
    expect(wrapper.find('[data-rascunho]').exists()).toBe(false);
  });

  it('nome que volta depois do salvar não traz a versão antiga', async () => {
    const wrapper = montar();
    await flushPromises();

    await renomearESalvar(wrapper, ['salvar', 'nome']);

    expect(duracaoNaTela(wrapper)).toBe(3);
    expect(wrapper.find('[data-rascunho]').exists()).toBe(false);
    expect(wrapper.text()).toContain('AUTOMACAO_LIVRE.EDITOR.VERSAO');
  });

  it('Ligar com rascunho salva primeiro e liga a versão nova', async () => {
    AutomacoesAPI.salvar.mockImplementation(async (_id, { receita }) => ({
      data: salva({ versao: { id: 12, numero: 3, receita } }),
    }));
    AutomacoesAPI.ligar.mockResolvedValue({
      data: { ativa: true, versao: { id: 12 } },
    });
    const wrapper = montar();
    await flushPromises();
    await trocarDuracao(wrapper, 3);

    await wrapper.find('[data-ligar]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.salvar).toHaveBeenCalledTimes(1);
    expect(AutomacoesAPI.ligar).toHaveBeenCalledWith(5, 12);
  });

  it('pergunta antes de sair com rascunho não salvo', async () => {
    const wrapper = montar();
    await flushPromises();
    const guarda = onBeforeRouteLeave.mock.calls.at(-1)[0];
    expect(guarda()).toBe(true);

    await trocarDuracao(wrapper, 3);
    const resposta = guarda();

    expect(dialogo.abrir).toHaveBeenCalled();
    wrapper.findComponent(DialogoFalso).vm.$emit('seguro');
    await expect(resposta).resolves.toBe(false);
  });

  it('mostra o que corrigir quando a ligação é recusada (422)', async () => {
    AutomacoesAPI.ligar.mockRejectedValue(
      respostaDeErro(422, {
        error: 'A receita tem problema',
        problemas: ['O campo placa não existe'],
      })
    );
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-ligar]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.ligar).toHaveBeenCalledWith(5, 11);
    expect(useAlert).toHaveBeenCalledWith('A receita tem problema');
    expect(wrapper.find('[data-problemas]').text()).toContain(
      'O campo placa não existe'
    );
  });

  it('marca o passo que o editor não conhece como ação avançada', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-passo="p2"] [data-avancada]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-passo="p1"] [data-avancada]').exists()).toBe(
      false
    );
  });

  it('a nova fica na tela até guardar, e então ganha endereço', async () => {
    rota.name = 'automacoes_livre_nova';
    rota.params = { accountId: 1 };
    AutomacoesAPI.create.mockResolvedValue({ data: salva({ id: 8 }) });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-porta-zero]').trigger('click');
    expect(wrapper.find('[data-ligar]').attributes('disabled')).toBeDefined();
    const confira = wrapper.findComponent(LivreConfira);
    confira.vm.$emit('alterar', 'gatilho');
    await flushPromises();
    wrapper.findComponent(AlterarFalso).vm.$emit('salvar', {
      tipo: 'gatilho',
      valor: { tipo: 'conversa.criada' },
    });
    confira.vm.$emit('inserir', { listaId: 'raiz', indice: 0 });
    await flushPromises();
    expect(wrapper.find('[data-seletor-falso]').attributes('data-aberto')).toBe(
      'true'
    );

    wrapper
      .findComponent(SeletorFalso)
      .vm.$emit('escolher', CATALOGO.passos[1]);
    await flushPromises();
    const novo = abertos.at(-1);
    expect(novo).toMatchObject({ novo: true, listaId: 'raiz', indice: 0 });
    wrapper.findComponent(AlterarFalso).vm.$emit('salvar', novo);
    await flushPromises();

    expect(AutomacoesAPI.salvar).not.toHaveBeenCalled();
    await wrapper.find('[data-guardar]').trigger('click');
    await flushPromises();

    expect(AutomacoesAPI.create).toHaveBeenCalledWith({
      nome: 'AUTOMACAO_LIVRE.EDITOR.NOVA',
      receita: {
        gatilho: { tipo: 'conversa.criada' },
        passos: [{ id: 'p1', tipo: 'parar' }],
      },
    });
    expect(rota.name).toBe('automacoes_livre_editar');
    expect(rota.params.id).toBe(8);
  });

  it('o "Se" sem passo fica só na tela até completar, e Ligar espera', async () => {
    const wrapper = montar();
    await flushPromises();
    const confira = wrapper.findComponent(LivreConfira);
    confira.vm.$emit('inserir', { listaId: 'raiz', indice: 2 });
    await flushPromises();
    wrapper.findComponent(SeletorFalso).vm.$emit('escolher', {
      tipo: 'se',
      grupo: 'CONTROLE',
      frase: 'SE',
      campos: [],
    });
    await flushPromises();
    const condicao = { campo: { $valor: 'conversa.status' }, op: 'vazio' };
    wrapper.findComponent(AlterarFalso).vm.$emit('salvar', {
      ...abertos.at(-1),
      valor: { ...abertos.at(-1).valor, condicao },
    });
    await flushPromises();

    expect(AutomacoesAPI.salvar).not.toHaveBeenCalled();
    expect(wrapper.find('[data-nao-salva]').exists()).toBe(true);
    expect(wrapper.find('[data-ligar]').attributes('disabled')).toBeDefined();
  });

  it('a nova começa pelas portas, e a receita abre na tela, desligada, com o nome dela', async () => {
    rota.name = 'automacoes_livre_nova';
    rota.params = { accountId: 1 };
    rota.query = {};
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-portas]').exists()).toBe(true);
    await wrapper.find('[data-receita]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-portas]').exists()).toBe(false);
    expect(wrapper.findComponent(LivreConfira).props('receita')).toEqual(
      CATALOGO.receitas[0].receita
    );
    expect(rota.query.receita).toBe('AGRADECER');
    expect(AutomacoesAPI.create).not.toHaveBeenCalled();
  });

  it('sem a flag que a receita pede, a porta fica desabilitada com o porquê, e ?receita não abre', async () => {
    flags.delete('automacao_mensagens');
    rota.name = 'automacoes_livre_nova';
    rota.params = { accountId: 1 };
    rota.query = { receita: 'AGRADECER' };
    const wrapper = montar();
    await flushPromises();

    const porta = wrapper.find('[data-receita]');
    expect(porta.attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-falta-flag]').text()).toBe(
      'AUTOMACAO_LIVRE.RECEITAS.REQUER.AUTOMACAO_MENSAGENS'
    );
    expect(wrapper.find('[data-portas]').exists()).toBe(true);
    flags.add('automacao_mensagens');
  });

  it('pergunta antes de sair com a nova ainda não guardada', async () => {
    rota.name = 'automacoes_livre_nova';
    rota.params = { accountId: 1 };
    const wrapper = montar();
    await flushPromises();
    const guarda = onBeforeRouteLeave.mock.calls.at(-1)[0];
    expect(guarda()).toBe(true);

    wrapper.findComponent(AlterarFalso).vm.$emit('salvar', {
      tipo: 'gatilho',
      valor: { tipo: 'conversa.criada' },
    });
    await flushPromises();
    const resposta = guarda();
    expect(dialogo.abrir).toHaveBeenCalled();
    wrapper.findComponent(DialogoFalso).vm.$emit('acao');
    await expect(resposta).resolves.toBe(true);
  });

  // #2499: com a flag, o "Alterar" recebe os gatilhos de card; trocar de
  // "entrou na etapa" para "card ganho" não leva a etapa junto, e a frase do
  // Confira diz a etapa escolhida.
  it.each([
    ['quem lê os valores', true, undefined],
    ['quem não lê os valores', false, true],
  ])(
    '%s: o catálogo do Alterar marca o valor do card',
    async (_caso, sim, marca) => {
      leValores.sim = sim;
      const valor = {
        caminho: 'card.valor',
        frase: 'VALOR',
        permissao: 'sales_value_view',
      };
      // O catálogo fica em cache no módulo: troca e volta, como no gatilho de card.
      const { catalogo } = useCatalogo();
      const antes = catalogo.value;
      catalogo.value = { ...CATALOGO, valores: [valor] };
      const wrapper = montar();
      await flushPromises();

      const valores = wrapper
        .findComponent(AlterarFalso)
        .props('catalogo').valores;
      catalogo.value = antes;
      expect(valores[0].sem_permissao).toBe(marca);
    }
  );

  it('gatilho de card: oferece com a flag e salva o gatilho inteiro', async () => {
    const ENTROU = {
      tipo: 'card.entrou_na_etapa',
      frase: 'AUTOMACAO_LIVRE.GATILHOS.CARD_ENTROU_NA_ETAPA',
      grupo: 'card',
      requer: 'automacao_gatilhos',
      funil: true,
      parametros: [
        { nome: 'etapa_id', peca: 'etapa', obrigatorio: true, frase: 'E' },
      ],
    };
    const GANHO = { ...ENTROU, tipo: 'card.ganho', parametros: undefined };
    // O catálogo fica guardado no módulo depois da primeira carga.
    const { catalogo } = useCatalogo();
    const antes = catalogo.value;
    catalogo.value = {
      ...CATALOGO,
      gatilhos: [...CATALOGO.gatilhos, ENTROU, GANHO],
    };
    const tiposOferecidos = wrapper =>
      wrapper
        .findComponent(AlterarFalso)
        .vm.$attrs.gatilhos.map(item => item.tipo);

    const semFlag = montar();
    await flushPromises();
    expect(tiposOferecidos(semFlag)).toEqual(['conversa.criada']);
    semFlag.unmount();

    flags.add('automacao_gatilhos');
    const wrapper = montar();
    await flushPromises();
    expect(tiposOferecidos(wrapper)).toEqual([
      'conversa.criada',
      'card.entrou_na_etapa',
      'card.ganho',
    ]);

    const alterar = wrapper.findComponent(AlterarFalso);
    alterar.vm.$emit('salvar', {
      tipo: 'gatilho',
      valor: { tipo: 'card.entrou_na_etapa', etapa_id: 12 },
    });
    await flushPromises();
    const confira = wrapper.findComponent(LivreConfira);
    expect(confira.find('[data-gatilho]').text()).toBe(
      'AUTOMACAO_LIVRE.GATILHO_COM.CARD_ENTROU_NA_ETAPA'
    );

    alterar.vm.$emit('salvar', {
      tipo: 'gatilho',
      valor: { tipo: 'card.ganho' },
    });
    await flushPromises();
    expect(confira.props('receita').gatilho).toEqual({ tipo: 'card.ganho' });
    flags.delete('automacao_gatilhos');
    catalogo.value = antes;
  });
});
