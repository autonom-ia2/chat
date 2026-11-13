import { computed, defineComponent, reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useModeloDeRamo } from '../../composables/useModeloDeRamo';
import { modeloDeRamo, ramoDaQuery } from '../../constants/modelosDeRamo';

// #2881 — o agente pronto por ramo na criação: antes da conversa, a tela fala primeiro com os textos do cartão; depois,
// vale o `modelo_pronto` do servidor (da conversa, ou do próprio rascunho quando ele é reaberto sem conversa). Cada
// mudança manda a lista inteira e a tela só mostra o que o servidor devolve.
const store = vi.hoisted(() => ({ dispatch: vi.fn(), state: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed: calcular } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => calcular(() => store.state[nome]),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const MODELO = {
  chave: 'seguro_garantia',
  ramo: 'Seguro garantia',
  nome_padrao: 'Assistente de Seguro Garantia',
  seguradoras_sugeridas: 'Junto Seguros, Pottencial e Tokio Marine',
  perguntas: [
    { id: 'p1', texto: 'Qual o CNPJ?', tirada: false },
    { id: 'p2', texto: 'Qual o valor?', tirada: false },
  ],
  documentos: [{ id: 'd1', texto: 'Edital.', tirada: false }],
  ferramentas: [
    { fonte: 'cnpj', usar_quando: 'Use quando vier o CNPJ da empresa.' },
    { fonte: 'inventada', usar_quando: 'Fora do catálogo.' },
  ],
  tambem: [{ fonte: 'cidades', usar_quando: 'Use quando vier a cidade.' }],
  premium: ['certidoes_empresa', 'inventada'],
  teste: ['O que é seguro garantia?', 'Quanto custa?'],
};

const prepararStore = () => {
  store.state = reactive({
    'autonomiaBuildThreads/getThread': null,
    'autonomiaBuildThreads/getModeloPronto': null,
  });
  store.dispatch.mockReset().mockResolvedValue(null);
  alerta.mockReset();
};
const comConversa = (modelo = MODELO) => {
  store.state['autonomiaBuildThreads/getThread'] = { id: 7, agent_id: 90 };
  store.state['autonomiaBuildThreads/getModeloPronto'] = modelo;
};

const montadas = [];
const usar = ({ pedido = 'seguro_garantia', agente = null } = {}) => {
  const conversa = { respostas: ref(0), fechada: ref(false) };
  const rascunho = ref(agente);
  let ramo;
  montadas.push(
    mount(
      defineComponent({
        setup() {
          ramo = useModeloDeRamo({
            pedido,
            conversa,
            agente: computed(() => rascunho.value),
          });
          return () => null;
        },
      })
    )
  );
  return { ramo, conversa, rascunho };
};

beforeEach(prepararStore);
afterEach(() => montadas.splice(0).forEach(wrapper => wrapper.unmount()));

describe('modelosDeRamo', () => {
  it('knows the three keys the server serves, and reads the choice from ?ramo=', () => {
    expect(
      ['seguro_auto', 'seguro_garantia', 'transporte_carga'].map(
        chave => modeloDeRamo(chave).chave
      )
    ).toEqual(['seguro_auto', 'seguro_garantia', 'transporte_carga']);
    expect(ramoDaQuery({ ramo: 'transporte_carga' })).toBe('transporte_carga');
    expect(ramoDaQuery({ ramo: 'seguro_de_vida' })).toBeNull();
    expect(ramoDaQuery({ modelo: 'seguro_auto' })).toBeNull();
    expect(ramoDaQuery()).toBeNull();
  });
});

describe('useModeloDeRamo', () => {
  it('before the conversation exists, speaks first with the texts of the chosen card', () => {
    const { ramo } = usar();

    expect(ramo.ativo.value).toBe(true);
    expect(ramo.modelo.value).toBeNull();
    expect(ramo.ramo.value).toBe('AGENTS.JORNADA.RAMOS.ITENS.GARANTIA.TITULO');
    expect(ramo.falaDeAbertura.value).toBe(
      'AGENTS.JORNADA.RAMOS.CRIAR.PERGUNTA_EMPRESA'
    );
    expect(ramo.exemploDoCampo.value).toBe(
      'AGENTS.JORNADA.RAMOS.CRIAR.EXEMPLO_EMPRESA'
    );
    expect(ramo.exemplo.value).toEqual([
      {
        de: 'cliente',
        texto: 'AGENTS.JORNADA.RAMOS.ITENS.GARANTIA.CLIENTE',
        hora: '11:08',
      },
      {
        de: 'agente',
        texto: 'AGENTS.JORNADA.RAMOS.ITENS.GARANTIA.AGENTE',
        hora: '11:08',
      },
    ]);
    expect(ramo.ideias.value).toEqual([]);
  });

  it('without a choice and without a model, it is off and gives nothing', () => {
    const { ramo } = usar({ pedido: null });

    expect(ramo.ativo.value).toBe(false);
    expect(ramo.exemplo.value).toBeNull();
    expect(ramo.perguntas.value).toEqual([]);
    expect(ramo.perguntasDeTeste.value).toEqual([]);
    expect(ramo.frases.value).toEqual({});
  });

  it('once the conversation exists, the server decides: an account without the model goes on as any agent', () => {
    const { ramo } = usar();
    comConversa(null);

    expect(ramo.ativo.value).toBe(false);
    expect(ramo.modelo.value).toBeNull();
    expect(ramo.exemplo.value).toBeNull();
  });

  it('with the model of the conversation, the lists and the test questions are the server ones', () => {
    const { ramo } = usar({ pedido: null });
    comConversa();

    expect(ramo.ativo.value).toBe(true);
    expect(ramo.perguntas.value).toEqual(MODELO.perguntas);
    expect(ramo.documentos.value).toEqual(MODELO.documentos);
    expect(ramo.perguntasDeTeste.value).toEqual(MODELO.teste);
  });

  it('shows one name for the line from start to end: the title of the card, never the long name the server writes to the AI', () => {
    const { ramo } = usar();
    const antes = ramo.ramo.value;
    comConversa({ ...MODELO, ramo: 'Seguro garantia por extenso' });

    expect(antes).toBe('AGENTS.JORNADA.RAMOS.ITENS.GARANTIA.TITULO');
    expect(ramo.ramo.value).toBe(antes);
  });

  it('a line this screen has no card for keeps the name the server sends', () => {
    const { ramo } = usar({ pedido: null });
    comConversa({ ...MODELO, chave: 'seguro_de_vida', ramo: 'Seguro de vida' });

    expect(ramo.ramo.value).toBe('Seguro de vida');
    expect(ramo.exemplo.value).toBeNull();
  });

  it('keeps only tools the showcase knows, and maps each one to its "Use when" sentence', () => {
    const { ramo } = usar();
    comConversa();

    expect(ramo.ferramentas.value).toEqual([MODELO.ferramentas[0]]);
    expect(ramo.tambem.value).toEqual(MODELO.tambem);
    expect(ramo.pagas.value).toEqual(['certidoes_empresa']);
    expect(ramo.frases.value).toEqual({
      cnpj: 'Use quando vier o CNPJ da empresa.',
      cidades: 'Use quando vier a cidade.',
    });
  });

  it('on the second question, suggests the insurers of the line and "decide later"', async () => {
    const { ramo, conversa } = usar();
    comConversa();
    expect(ramo.ideias.value).toEqual([]);

    conversa.respostas.value = 1;
    expect(ramo.ideias.value).toEqual([
      'Junto Seguros, Pottencial e Tokio Marine',
      'AGENTS.JORNADA.RAMOS.CRIAR.DECIDO_DEPOIS',
    ]);
    expect(ramo.exemploDoCampo.value).toBe(
      'AGENTS.JORNADA.RAMOS.CRIAR.EXEMPLO_SEGURADORAS'
    );

    conversa.respostas.value = 2;
    conversa.fechada.value = true;
    expect(ramo.ideias.value).toEqual([]);
    expect(ramo.exemploDoCampo.value).toBe('');
  });

  it('a change patches the conversation with the whole new list', async () => {
    const { ramo } = usar();
    comConversa();
    const nova = [
      { ...MODELO.perguntas[0], tirada: true },
      MODELO.perguntas[1],
    ];

    await ramo.mudar('perguntas', nova);

    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/mudarModeloPronto',
      { threadId: 7, listas: { perguntas: nova } }
    );
    expect(ramo.gravando.value.perguntas).toBe(false);
    expect(alerta).not.toHaveBeenCalled();
  });

  it('while a list is being saved, another request for the same list is not accepted; another list waits its turn', async () => {
    const { ramo } = usar();
    comConversa();
    let responder;
    store.dispatch.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          responder = resolve;
        })
    );

    const primeira = ramo.mudar('perguntas', [MODELO.perguntas[0]]);
    expect(ramo.gravando.value.perguntas).toBe(true);
    await ramo.mudar('perguntas', []);
    const segunda = ramo.mudar('documentos', []);
    await flushPromises();

    // One request at a time for the whole model: the answers can never arrive out of order.
    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(ramo.gravando.value.documentos).toBe(true);
    responder();
    await primeira;
    await segunda;
    expect(store.dispatch).toHaveBeenCalledTimes(2);
    expect(store.dispatch.mock.calls[1][1].listas).toEqual({ documentos: [] });
    expect(ramo.gravando.value).toEqual({
      perguntas: false,
      documentos: false,
    });
  });

  it('a refused change warns in one short sentence and the list stays as the server has it', async () => {
    const { ramo } = usar();
    comConversa();
    store.dispatch.mockRejectedValue({
      response: { status: 422, data: { motivo: 'texto_invalido' } },
    });

    await ramo.mudar('perguntas', []);
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith(
      'AGENTS.JORNADA.RAMOS.CONFIRA.ERRO_AO_MUDAR'
    );
    expect(ramo.perguntas.value).toEqual(MODELO.perguntas);
    expect(ramo.gravando.value.perguntas).toBe(false);
  });

  it('tells who asked that the change was saved, and says nothing when the server refuses', async () => {
    const { ramo } = usar();
    comConversa();
    const aoGravar = vi.fn();

    await ramo.mudar('perguntas', [], aoGravar);
    expect(aoGravar).toHaveBeenCalledTimes(1);

    store.dispatch.mockRejectedValue({
      response: { status: 422, data: { motivo: 'texto_invalido' } },
    });
    await ramo.mudar('perguntas', [], aoGravar);

    expect(aoGravar).toHaveBeenCalledTimes(1);
    expect(alerta).toHaveBeenCalledTimes(1);
  });

  it('an agent that already started has its own warning', async () => {
    const { ramo } = usar();
    comConversa();
    store.dispatch.mockRejectedValue({
      response: { status: 422, data: { motivo: 'agente_ja_comecou' } },
    });

    await ramo.mudar('ferramentas', []);

    expect(alerta).toHaveBeenCalledWith(
      'AGENTS.JORNADA.RAMOS.CONFIRA.ERRO_JA_COMECOU'
    );
  });

  it('a reopened draft (no conversation) reads the model from the agent and saves through the agent', async () => {
    const { ramo } = usar({
      pedido: null,
      agente: { id: 90, modelo_pronto: MODELO },
    });

    expect(ramo.ativo.value).toBe(true);
    expect(ramo.ramo.value).toBe('AGENTS.JORNADA.RAMOS.ITENS.GARANTIA.TITULO');
    expect(ramo.documentos.value).toEqual(MODELO.documentos);
    expect(ramo.frases.value.cnpj).toBe('Use quando vier o CNPJ da empresa.');

    const nova = [{ ...MODELO.documentos[0], tirada: true }];
    await ramo.mudar('documentos', nova);

    expect(store.dispatch).toHaveBeenCalledTimes(1);
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaAgents/mudarModeloPronto',
      { agentId: 90, listas: { documentos: nova } }
    );
  });

  it('with a conversation that has the model, the conversation wins over the agent copy', async () => {
    const { ramo } = usar({
      pedido: null,
      agente: { id: 90, modelo_pronto: { ...MODELO, perguntas: [] } },
    });
    expect(ramo.perguntas.value).toEqual([]);
    comConversa();

    expect(ramo.perguntas.value).toEqual(MODELO.perguntas);
    await ramo.mudar('perguntas', []);
    expect(store.dispatch.mock.calls[0][0]).toBe(
      'autonomiaBuildThreads/mudarModeloPronto'
    );
  });

  it('without any model, a change asks nothing of the server', async () => {
    const { ramo } = usar();

    await ramo.mudar('perguntas', []);

    expect(store.dispatch).not.toHaveBeenCalled();
  });
});
