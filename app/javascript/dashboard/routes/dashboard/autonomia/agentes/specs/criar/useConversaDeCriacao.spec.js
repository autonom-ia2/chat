import { defineComponent, nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import {
  useConversaDeCriacao,
  ESPERA_DEMORANDO_MS,
} from '../../composables/useConversaDeCriacao';

const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  commit: vi.fn(),
  state: null,
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state[nome]),
  };
});
const fotos = vi.hoisted(() => ({ upload: vi.fn() }));
vi.mock('dashboard/api/autonomia/builderImages', () => ({ default: fotos }));
const conversaApi = vi.hoisted(() => ({ sendMessage: vi.fn() }));
vi.mock('dashboard/api/autonomia/buildThreads', () => ({
  default: conversaApi,
}));

const prepararStore = (extra = {}) => {
  store.state = reactive({
    'autonomiaBuildThreads/getMessages': [],
    'autonomiaBuildThreads/getStatus': null,
    'autonomiaBuildThreads/getPhase': 'interviewing',
    'autonomiaBuildThreads/getError': null,
    'autonomiaBuildThreads/getThread': null,
    'autonomiaBuildThreads/getAgent': null,
    'autonomiaBuildThreads/getUIFlags': { creating: false, sending: false },
    'autonomiaSources/getSources': [],
    ...extra,
  });
  store.dispatch.mockReset();
  store.dispatch.mockResolvedValue(null);
  store.commit.mockReset();
  conversaApi.sendMessage.mockReset().mockResolvedValue({ data: {} });
  fotos.upload.mockReset();
};

const montar = (opcoes = { modelo: 'support' }) => {
  let conversa;
  const Casca = defineComponent({
    setup() {
      conversa = useConversaDeCriacao(opcoes);
      return () => null;
    },
  });
  const wrapper = mount(Casca);
  return { conversa, wrapper };
};

const chamadas = acao =>
  store.dispatch.mock.calls.filter(([nome]) => nome === acao);
const arquivo = (nome, tipo, tamanho = 1000) => {
  const f = new File(['x'], nome, { type: tipo });
  Object.defineProperty(f, 'size', { value: tamanho });
  return f;
};
const comThread = (id = 7, agentId = 90) => {
  store.state['autonomiaBuildThreads/getThread'] = { id, agent_id: agentId };
};
const respondeu = vezes => {
  store.state['autonomiaBuildThreads/getMessages'] = Array.from(
    { length: vezes },
    (_, i) => [
      { role: 'assistant', content: `Pergunta ${i}` },
      { role: 'user', content: `Resposta ${i}` },
    ]
  ).flat();
};

describe('useConversaDeCriacao', () => {
  beforeEach(() => prepararStore());

  it('opens the Builder with only the model, so the AI speaks first (no message)', () => {
    const { conversa } = montar({ modelo: 'sdr' });
    conversa.comecar();

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/start', {
      type: 'sdr',
      actuation: 'external',
      with_knowledge: true,
    });
    expect(chamadas('autonomiaBuildThreads/start')[0][1]).not.toHaveProperty(
      'message'
    );
  });

  it('continues a draft that already has an instruction straight into the test, without opening a thread', async () => {
    const { conversa } = montar();
    await conversa.continuar({ id: 4, name: 'Lia', has_instruction: true });

    expect(chamadas('autonomiaBuildThreads/start')).toHaveLength(0);
    expect(conversa.fechada.value).toBe(true);
    expect(conversa.agenteId.value).toBe(4);
    expect(conversa.falas.value.map(f => f.texto)).toEqual([
      'AGENTS.JORNADA.CRIAR.CONTE.CONTINUAR',
      'AGENTS.JORNADA.CRIAR.CONTE.FECHOU',
    ]);
  });

  it('continues a draft without instruction by reopening the Builder tied to it', async () => {
    const { conversa } = montar();
    await conversa.continuar({ id: 4, name: 'Lia', has_instruction: false });

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/start', {
      agentId: 4,
    });
    expect(conversa.fechada.value).toBe(false);
  });

  it('sends a typed answer as the next turn of the open thread', async () => {
    comThread();
    const { conversa } = montar();
    await conversa.enviar({ texto: ' Loja de roupas ' });

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/send', {
      threadId: 7,
      content: 'Loja de roupas',
      extra: {},
    });
  });

  it('reopens the thread with the message when the first start had failed', async () => {
    const { conversa } = montar({ modelo: 'reception' });
    await conversa.enviar({ texto: 'Oi' });

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/start', {
      type: 'reception',
      actuation: 'external',
      with_knowledge: true,
      message: 'Oi',
    });
  });

  it('does not send while the AI is still answering, and says why', async () => {
    comThread();
    store.state['autonomiaBuildThreads/getStatus'] = 'processing';
    const { conversa } = montar();
    const enviou = await conversa.enviar({ texto: 'Oi' });

    expect(enviou).toBe(false);
    expect(chamadas('autonomiaBuildThreads/send')).toHaveLength(0);
    expect(conversa.aviso.value).toBe('espere');
  });

  it('turns a 409 (build in progress) into the same "wait" notice, without an error card', async () => {
    comThread();
    store.dispatch.mockImplementation(async acao => {
      if (acao === 'autonomiaBuildThreads/send') {
        throw Object.assign(new Error('409'), { response: { status: 409 } });
      }
      return null;
    });
    const { conversa } = montar();
    const aceito = await conversa.enviar({ texto: 'Oi' });

    expect(conversa.aviso.value).toBe('espere');
    expect(conversa.falhou.value).toBe(false);
    // A tela devolve o texto ao campo: o turno não entrou.
    expect(aceito).toBe(false);
  });

  it('does not send a second turn while the photos of the first are still uploading', async () => {
    comThread();
    let subir;
    fotos.upload.mockReturnValue(
      new Promise(resolve => {
        subir = resolve;
      })
    );
    const { conversa } = montar();
    const primeiro = conversa.enviar({
      texto: 'Minha vitrine',
      anexos: [arquivo('v.png', 'image/png')],
    });
    expect(conversa.pensando.value).toBe(true);
    const segundo = await conversa.enviar({ texto: 'Outra coisa' });

    expect(segundo).toBe(false);
    expect(conversa.aviso.value).toBe('espere');
    subir({ data: { signed_id: 'img-1' } });
    await primeiro;
    expect(chamadas('autonomiaBuildThreads/send')).toHaveLength(1);
    expect(conversa.pensando.value).toBe(false);
  });

  it('keeps a file in line until the draft exists, then sends it to the knowledge base', async () => {
    const { conversa } = montar();
    await conversa.enviar({
      anexos: [arquivo('tabela.pdf', 'application/pdf')],
    });

    expect(chamadas('autonomiaSources/create')).toHaveLength(0);
    expect(conversa.estadoDoMaterial(conversa.materiais.value[0])).toBe('fila');
    // Nada vai para o Construtor: arquivo sozinho não é turno.
    expect(chamadas('autonomiaBuildThreads/start')).toHaveLength(0);

    store.dispatch.mockImplementation(async acao =>
      acao === 'autonomiaSources/create' ? { id: 31 } : null
    );
    comThread(7, 90);
    await nextTick();
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/create', {
      agentId: 90,
      descriptor: { file: expect.any(File), kind: 'knowledge' },
    });
    expect(conversa.materiais.value[0].fonteId).toBe(31);
  });

  it('refuses a file over 25 MB before uploading it', async () => {
    comThread();
    const { conversa } = montar();
    await conversa.enviar({
      anexos: [arquivo('catalogo.pdf', 'application/pdf', 26 * 1024 * 1024)],
    });

    expect(chamadas('autonomiaSources/create')).toHaveLength(0);
    expect(conversa.estadoDoMaterial(conversa.materiais.value[0])).toBe(
      'grande'
    );
  });

  it('reads the material state from the knowledge base', async () => {
    comThread();
    store.dispatch.mockImplementation(async acao =>
      acao === 'autonomiaSources/create' ? { id: 31 } : null
    );
    const { conversa } = montar();
    await conversa.enviar({ anexos: [arquivo('t.pdf', 'application/pdf')] });
    await flushPromises();
    const material = () => conversa.materiais.value[0];

    expect(conversa.estadoDoMaterial(material())).toBe('lendo');
    store.state['autonomiaSources/getSources'] = [
      { id: 31, status: 'ready', review: { status: 'accepted' } },
    ];
    expect(conversa.estadoDoMaterial(material())).toBe('pronto');
    store.state['autonomiaSources/getSources'] = [
      { id: 31, status: 'ready', review: { status: 'needs_resend' } },
    ];
    expect(conversa.estadoDoMaterial(material())).toBe('atencao');
  });

  it('keeps the last known state of a material while the knowledge base reloads (no blinking)', async () => {
    comThread();
    store.dispatch.mockImplementation(async acao =>
      acao === 'autonomiaSources/create' ? { id: 31 } : null
    );
    const { conversa } = montar();
    await conversa.enviar({ anexos: [arquivo('t.pdf', 'application/pdf')] });
    await flushPromises();
    const material = () => conversa.materiais.value[0];

    store.state['autonomiaSources/getSources'] = [
      { id: 31, status: 'ready', review: { status: 'accepted' } },
    ];
    expect(conversa.estadoDoMaterial(material())).toBe('pronto');
    // A store esvazia a lista a cada leitura antes de a resposta chegar.
    store.state['autonomiaSources/getSources'] = [];
    expect(conversa.estadoDoMaterial(material())).toBe('pronto');
  });

  it('sends photos with the turn (builder_images), never to the knowledge base', async () => {
    comThread();
    fotos.upload.mockResolvedValue({ data: { signed_id: 'img-1' } });
    const { conversa } = montar();
    await conversa.enviar({
      texto: 'Minha tabela',
      anexos: [arquivo('t.png', 'image/png')],
    });

    expect(chamadas('autonomiaSources/create')).toHaveLength(0);
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/send', {
      threadId: 7,
      content: 'Minha tabela',
      extra: { image_signed_ids: ['img-1'] },
    });
    expect(conversa.estadoDoMaterial(conversa.materiais.value[0])).toBe(
      'pronto'
    );
  });

  it('gives a photo with no text a short turn of its own', async () => {
    comThread();
    fotos.upload.mockResolvedValue({ data: { signed_id: 'img-2' } });
    const { conversa } = montar();
    await conversa.enviar({ anexos: [arquivo('t.png', 'image/png')] });

    expect(chamadas('autonomiaBuildThreads/send')[0][1].content).toBe(
      'AGENTS.JORNADA.CRIAR.CONTE.FOTO'
    );
  });

  // Ordem real da store no onSettled: SET_PHASE('reviewing') e, depois do GET do agente, SET_AGENT.
  it('closes when the Builder generates the agent, and counts one update per new close (real store order)', async () => {
    comThread(7, 90);
    const { conversa } = montar();
    store.state['autonomiaBuildThreads/getPhase'] = 'reviewing';
    await nextTick();
    store.state['autonomiaBuildThreads/getAgent'] = { id: 90, name: 'Duda' };
    await nextTick();
    expect(conversa.fechada.value).toBe(true);
    expect(conversa.atualizacoes.value).toBe(0);

    store.state['autonomiaBuildThreads/getPhase'] = 'interviewing';
    await nextTick();
    store.state['autonomiaBuildThreads/getPhase'] = 'reviewing';
    await nextTick();
    store.state['autonomiaBuildThreads/getAgent'] = { id: 90, name: 'Duda' };
    await nextTick();
    expect(conversa.atualizacoes.value).toBe(1);
  });

  it('closes even when the store could not read the agent, and reads it apart', async () => {
    comThread(7, 90);
    const { conversa } = montar();
    // onSettled: fase reviewing; o autonomiaAgents/show falhou e o SET_AGENT nunca vem.
    store.state['autonomiaBuildThreads/getPhase'] = 'reviewing';
    await nextTick();

    expect(conversa.fechada.value).toBe(true);
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 90);
  });

  it('"Test now" force-closes only after two answers, with the language-independent signal', async () => {
    comThread();
    respondeu(1);
    const { conversa } = montar();
    expect(conversa.podeTestarAgora.value).toBe(false);
    conversa.testarAgora();
    expect(chamadas('autonomiaBuildThreads/completeMaterials')).toHaveLength(0);

    respondeu(2);
    await nextTick();
    conversa.testarAgora();
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/completeMaterials',
      { threadId: 7, content: 'AGENTS.BUILDER.FINALIZE_SIGNAL' }
    );
    expect(conversa.podeTestarAgora.value).toBe(false);
  });

  it('does not offer "Test now" while the AI is still answering (it would get a 409)', () => {
    comThread();
    respondeu(2);
    store.state['autonomiaBuildThreads/getStatus'] = 'processing';
    const { conversa } = montar();
    expect(conversa.podeTestarAgora.value).toBe(false);
  });

  it('retries a failed build through the retry endpoint, and falls back to polling', async () => {
    comThread();
    store.state['autonomiaBuildThreads/getError'] = 'failed';
    store.dispatch.mockImplementation(async acao => {
      if (acao === 'autonomiaBuildThreads/retry') throw new Error('422');
      return null;
    });
    const { conversa } = montar();
    await conversa.tentarDeNovo();

    expect(store.commit).toHaveBeenCalledWith(
      'autonomiaBuildThreads/SET_ERROR',
      null
    );
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/poll', {
      threadId: 7,
    });
  });

  it('resends the turn that failed to send, with the same text and photos (never retries the build)', async () => {
    comThread();
    fotos.upload.mockResolvedValue({ data: { signed_id: 'img-1' } });
    let vezes = 0;
    store.dispatch.mockImplementation(async (acao, dados) => {
      if (acao !== 'autonomiaBuildThreads/send') return null;
      vezes += 1;
      if (vezes > 1) return null;
      // Como a store: o eco fica na conversa e o erro vira 'send'.
      store.state['autonomiaBuildThreads/getMessages'] = [
        { role: 'user', content: dados.content, local: true },
      ];
      store.state['autonomiaBuildThreads/getError'] = 'send';
      throw new Error('500');
    });
    const { conversa } = montar();
    await conversa.enviar({
      texto: 'Minha tabela',
      anexos: [arquivo('t.png', 'image/png')],
    });
    expect(conversa.falhou.value).toBe(true);
    await conversa.tentarDeNovo();

    expect(chamadas('autonomiaBuildThreads/retry')).toHaveLength(0);
    expect(chamadas('autonomiaBuildThreads/send')).toHaveLength(2);
    // O eco já está na tela: não repete o balão.
    expect(chamadas('autonomiaBuildThreads/send')[1][1]).toEqual({
      threadId: 7,
      content: 'Minha tabela',
      extra: { image_signed_ids: ['img-1'] },
      echo: false,
    });
    expect(fotos.upload).toHaveBeenCalledTimes(1);
  });

  it('reopens a first turn that failed with the same message and photos', async () => {
    fotos.upload.mockResolvedValue({ data: { signed_id: 'img-1' } });
    let vezes = 0;
    store.dispatch.mockImplementation(async acao => {
      if (acao !== 'autonomiaBuildThreads/start') return null;
      vezes += 1;
      if (vezes > 1) return null;
      store.state['autonomiaBuildThreads/getError'] = 'send';
      throw new Error('500');
    });
    const { conversa } = montar({ modelo: 'sdr' });
    await conversa.enviar({
      texto: 'Vendo bolos',
      anexos: [arquivo('b.png', 'image/png')],
    });
    await conversa.tentarDeNovo();

    expect(chamadas('autonomiaBuildThreads/start')[1][1]).toEqual({
      type: 'sdr',
      actuation: 'external',
      with_knowledge: true,
      message: 'Vendo bolos',
      image_signed_ids: ['img-1'],
    });
  });

  it('retries a start that never opened by opening it again', async () => {
    const { conversa } = montar({ modelo: 'support' });
    await conversa.tentarDeNovo();
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/start', {
      type: 'support',
      actuation: 'external',
      with_knowledge: true,
    });
  });

  it('shows "taking longer than usual" after a minute thinking', async () => {
    vi.useFakeTimers();
    comThread();
    const { conversa } = montar();
    store.state['autonomiaBuildThreads/getStatus'] = 'processing';
    await nextTick();
    vi.advanceTimersByTime(ESPERA_DEMORANDO_MS - 1);
    expect(conversa.demorando.value).toBe(false);
    vi.advanceTimersByTime(1);
    expect(conversa.demorando.value).toBe(true);

    store.state['autonomiaBuildThreads/getStatus'] = 'ready';
    await nextTick();
    expect(conversa.demorando.value).toBe(false);
    vi.useRealTimers();
  });

  it('stops polling and clears the stores when leaving', () => {
    const { wrapper } = montar();
    wrapper.unmount();

    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/stopPolling'
    );
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/stopPolling');
    expect(store.commit).toHaveBeenCalledWith('autonomiaBuildThreads/RESET');
    expect(store.commit).toHaveBeenCalledWith('autonomiaSources/SET', []);
  });

  // Direto na API, sem a store: a resposta não volta a ligar o poll nem a encher a store já limpa.
  it('closes on the server when leaving with two answers, so the draft keeps an instruction', () => {
    comThread();
    respondeu(2);
    const { wrapper } = montar();
    wrapper.unmount();
    expect(conversaApi.sendMessage).toHaveBeenCalledWith(
      7,
      'AGENTS.BUILDER.FINALIZE_SIGNAL',
      { force_close: true }
    );
    expect(chamadas('autonomiaBuildThreads/completeMaterials')).toHaveLength(0);
    expect(chamadas('autonomiaBuildThreads/send')).toHaveLength(0);
  });

  it('does not touch the server when leaving early or after it closed', async () => {
    comThread();
    respondeu(1);
    const cedo = montar();
    cedo.wrapper.unmount();
    expect(chamadas('autonomiaBuildThreads/completeMaterials')).toHaveLength(0);

    respondeu(3);
    const fechou = montar();
    await fechou.conversa.continuar({ id: 4, has_instruction: true });
    fechou.wrapper.unmount();
    expect(chamadas('autonomiaBuildThreads/completeMaterials')).toHaveLength(0);
    expect(conversaApi.sendMessage).not.toHaveBeenCalled();
  });

  it('removes a material from the conversation and from the knowledge base', async () => {
    comThread();
    store.dispatch.mockImplementation(async acao =>
      acao === 'autonomiaSources/create' ? { id: 31 } : null
    );
    const { conversa } = montar();
    await conversa.enviar({ anexos: [arquivo('t.pdf', 'application/pdf')] });
    await flushPromises();
    conversa.tirar(conversa.materiais.value[0]);

    expect(conversa.materiais.value).toHaveLength(0);
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/remove', {
      agentId: 90,
      sourceId: 31,
    });
  });

  it('orders the conversation: front lines, turns and materials where they were sent', async () => {
    comThread();
    respondeu(1);
    store.dispatch.mockImplementation(async acao =>
      acao === 'autonomiaSources/create' ? { id: 31 } : null
    );
    const { conversa } = montar();
    await conversa.enviar({ anexos: [arquivo('t.pdf', 'application/pdf')] });
    expect(conversa.falas.value.map(f => f.de)).toEqual([
      'assistente',
      'voce',
      'material',
    ]);
  });
});
