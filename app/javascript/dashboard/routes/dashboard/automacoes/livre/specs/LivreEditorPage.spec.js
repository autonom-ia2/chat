import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { onBeforeRouteLeave, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import LivreEditorPage from '../pages/LivreEditorPage.vue';
import LivreConfira from '../components/LivreConfira.vue';

// #2414 F5 — o editor: a nova fica na tela até guardar ou ligar; a salva vira
// versão a cada "Salvar", levando a versão vista; 409 recarrega; 422 mostra o
// que corrigir; o passo avançado volta idêntico.
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
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: criarRef } = await import('vue');
  const podeMudar = criarRef(true);
  return { useCanManage: () => podeMudar };
});
vi.mock('dashboard/composables/store', async () => {
  const { ref: criarRef } = await import('vue');
  return {
    useStore: () => ({ dispatch: vi.fn() }),
    useMapGetter: getter =>
      getter === 'attributes/getAttributesByModel'
        ? criarRef(() => [])
        : criarRef([]),
  };
});
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: {
    passos: vi.fn(),
    show: vi.fn(),
    salvar: vi.fn(),
    create: vi.fn(),
    ligar: vi.fn(),
    desligar: vi.fn(),
    renomear: vi.fn(),
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

// Os painéis de verdade usam o SidePanel; aqui guardam o que abriram.
const abertos = [];
const AlterarFalso = defineComponent({
  name: 'LivreAlterar',
  setup(_, { expose }) {
    expose({ abrir: item => abertos.push(item), fechar: vi.fn() });
  },
  template: '<div data-alterar-falso />',
});
const SeletorFalso = defineComponent({
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
});

const dialogo = { abrir: vi.fn() };
const DialogoFalso = defineComponent({
  name: 'DialogoDaCasa',
  setup(_, { expose }) {
    expose({ abrir: () => dialogo.abrir() });
  },
  template: '<div data-dialogo-falso />',
});

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
    rota.name = 'automacoes_livre_editar';
    rota.params = { accountId: 1, id: 5 };
    rota.query = {};
    AutomacoesAPI.passos.mockResolvedValue({ data: CATALOGO });
    AutomacoesAPI.show.mockResolvedValue({ data: salva() });
  });

  it.each([
    [true, true],
    [false, false],
  ])(
    'ligada=%s mostra o aviso de que a mudança vale na hora: %s',
    async (ativa, aparece) => {
      AutomacoesAPI.show.mockResolvedValue({ data: salva({ ativa }) });
      const wrapper = montar();
      await flushPromises();

      expect(wrapper.find('[data-ligada]').exists()).toBe(aparece);
    }
  );

  it('salva cada mudança como versão nova sobre a versão vista', async () => {
    AutomacoesAPI.salvar.mockResolvedValue({
      data: salva({
        versao: { id: 12, numero: 3, receita: salva().versao.receita },
      }),
    });
    const wrapper = montar();
    await flushPromises();

    wrapper.findComponent(LivreConfira).vm.$emit('alterar', 'p1');
    await flushPromises();
    expect(abertos[0]).toMatchObject({ tipo: 'passo', valor: { id: 'p1' } });

    const trocado = {
      ...abertos[0].valor,
      duracao: { valor: 3, unidade: 'dias' },
    };
    wrapper
      .findComponent(AlterarFalso)
      .vm.$emit('salvar', { tipo: 'passo', valor: trocado });
    await flushPromises();

    expect(AutomacoesAPI.salvar).toHaveBeenCalledTimes(1);
    const [id, { receita, baseVersaoId }] = AutomacoesAPI.salvar.mock.calls[0];
    expect(id).toBe(5);
    expect(baseVersaoId).toBe(11);
    expect(receita.passos[0].duracao.valor).toBe(3);
    expect(receita.passos[1]).toEqual(AVANCADO);
    expect(useAlert).toHaveBeenCalledWith('AUTOMACAO_LIVRE.EDITOR.SALVOU');
  });

  it('recarrega e avisa quando outra pessoa salvou no meio (409)', async () => {
    AutomacoesAPI.salvar.mockRejectedValue(respostaDeErro(409));
    const wrapper = montar();
    await flushPromises();

    wrapper
      .findComponent(AlterarFalso)
      .vm.$emit('tirar', { tipo: 'passo', valor: { id: 'p1' } });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('AUTOMACAO_LIVRE.MUDOU');
    expect(AutomacoesAPI.show).toHaveBeenCalledTimes(2);
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
});
