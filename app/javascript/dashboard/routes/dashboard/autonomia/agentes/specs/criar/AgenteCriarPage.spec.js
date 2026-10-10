import { nextTick, reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgenteCriarPage from '../../pages/AgenteCriarPage.vue';

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

const rota = vi.hoisted(() => ({ atual: null }));
const router = vi.hoisted(() => ({
  push: vi.fn(),
  replace: vi.fn(),
  resolve: vi.fn(destino => ({ href: `/app/${destino.name}` })),
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota.atual,
  useRouter: () => router,
}));

const tela = vi.hoisted(() => ({ celular: null }));
vi.mock('@vueuse/core', async original => ({
  ...(await original()),
  useMediaQuery: () => tela.celular,
}));

const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => true),
      podeEscolherQuemRecebe: computed(() => true),
    }),
  };
});

const jornada = vi.hoisted(() => ({
  canaisOcupados: vi.fn(),
  semana: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: jornada }));
const canaisApi = vi.hoisted(() => ({
  get: vi.fn(),
  connect: vi.fn(),
  disconnect: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canaisApi }));
vi.mock('dashboard/api/autonomia/builderImages', () => ({
  default: { upload: vi.fn() },
}));

const L2 = [
  {
    inbox_id: 10,
    name: 'WhatsApp da Loja',
    channel_type: 'Channel::Whatsapp',
    occupied_by: null,
  },
  {
    inbox_id: 11,
    name: 'WhatsApp do Centro',
    channel_type: 'Channel::Whatsapp',
    occupied_by: { kind: 'agent', agent_id: 9, agent_name: 'Bia' },
  },
];

const AGENTE = {
  id: 90,
  name: 'Duda',
  status: 'draft',
  enabled: false,
  actuation: 'external',
  has_instruction: true,
  config: { response_window: 'always' },
};

let ordem = [];
const prepararStore = ({ agente = AGENTE, falhaShow = false, teste } = {}) => {
  ordem = [];
  store.state = reactive({
    'autonomiaBuildThreads/getMessages': [],
    'autonomiaBuildThreads/getStatus': null,
    'autonomiaBuildThreads/getPhase': 'interviewing',
    'autonomiaBuildThreads/getError': null,
    'autonomiaBuildThreads/getThread': null,
    'autonomiaBuildThreads/getAgent': null,
    'autonomiaBuildThreads/getUIFlags': { creating: false, sending: false },
    'autonomiaSources/getSources': [],
    'autonomiaAgents/getRecords': [],
    'inboxes/getInboxes': [],
    getCurrentAccountId: 1,
    'accounts/getAccount': () => ({ id: 1, name: 'Loja da Ana' }),
  });
  store.commit.mockReset();
  store.dispatch.mockReset();
  store.dispatch.mockImplementation(async (acao, dados) => {
    ordem.push(acao);
    if (acao === 'autonomiaBuildThreads/start') {
      store.state['autonomiaBuildThreads/getThread'] = {
        id: 7,
        agent_id: null,
      };
      store.state['autonomiaBuildThreads/getStatus'] = 'processing';
    }
    if (acao === 'autonomiaAgents/show') {
      if (falhaShow) throw new Error('500');
      store.state['autonomiaAgents/getRecords'] = [agente];
      return agente;
    }
    if (acao === 'autonomiaAgents/test') {
      if (teste instanceof Error) throw teste;
      return (
        teste || { reply: 'Abrimos sim, das 9h às 13h.', used_knowledge: [] }
      );
    }
    if (acao === 'autonomiaAgents/update') {
      store.state['autonomiaAgents/getRecords'] = store.state[
        'autonomiaAgents/getRecords'
      ].map(item => (item.id === dados.id ? { ...item, ...dados } : item));
      return null;
    }
    return null;
  });
};

// O Construtor gerou o agente (fase reviewing), como a store faz no onSettled.
const conversaFecha = () => {
  store.state['autonomiaBuildThreads/getThread'] = { id: 7, agent_id: 90 };
  store.state['autonomiaBuildThreads/getStatus'] = 'ready';
  store.state['autonomiaBuildThreads/getAgent'] = AGENTE;
  store.state['autonomiaAgents/getRecords'] = [AGENTE];
  store.state['autonomiaBuildThreads/getPhase'] = 'reviewing';
};

// router.replace/push mudam a query da rota, como o vue-router faz na mesma rota.
const prepararRota = query => {
  rota.atual = reactive({ name: 'autonomia_agents_builder', query });
  const navegar = async destino => {
    if (destino.query) rota.atual.query = { ...destino.query };
  };
  router.push.mockReset();
  router.replace.mockReset();
  router.push.mockImplementation(navegar);
  router.replace.mockImplementation(navegar);
};

const montar = async ({
  query = { modelo: 'support' },
  celular = false,
} = {}) => {
  prepararRota(query);
  tela.celular = ref(celular);
  const wrapper = mount(AgenteCriarPage, { attachTo: document.body });
  await flushPromises();
  return wrapper;
};

const corpo = () => document.body;
const secaoDaConversa = wrapper =>
  wrapper
    .findAll('section')
    .find(secao => secao.find('[data-conversa]').exists());
// Troca uma ação da store sem perder o resto do mock.
const falharAcao = (nome, erro) => {
  const original = store.dispatch.getMockImplementation();
  store.dispatch.mockImplementation(async (acao, dados) => {
    if (acao === nome) {
      ordem.push(acao);
      throw erro;
    }
    return original(acao, dados);
  });
};
const conflito = () =>
  Object.assign(new Error('409'), { response: { status: 409 } });
const etapaAtual = () =>
  corpo()
    .querySelector('[aria-current="step"] [data-nome]')
    ?.textContent.trim();

describe('AgenteCriarPage', () => {
  beforeEach(() => {
    prepararStore();
    jornada.canaisOcupados.mockResolvedValue({ data: { payload: L2 } });
    canaisApi.get.mockReset();
    canaisApi.connect.mockReset().mockImplementation(async (id, inbox) => {
      ordem.push(`post:${id}:${inbox}`);
    });
    canaisApi.disconnect.mockReset().mockImplementation(async (id, inbox) => {
      ordem.push(`delete:${id}:${inbox}`);
    });
    alerta.mockReset();
    vi.stubGlobal('navigator', { onLine: true });
  });
  afterEach(() => {
    document.body.innerHTML = '';
    vi.unstubAllGlobals();
  });

  it('opens the Builder for the model in the query, clean and with the AI speaking first', async () => {
    const wrapper = await montar({ query: { modelo: 'sdr' } });

    expect(store.commit).toHaveBeenCalledWith('autonomiaBuildThreads/RESET');
    expect(store.commit).toHaveBeenCalledWith('autonomiaSources/SET', []);
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaBuildThreads/start', {
      type: 'sdr',
      actuation: 'external',
      with_knowledge: true,
    });
    expect(etapaAtual()).toBe('AGENTS.JORNADA.CRIAR.ETAPAS.CONTE');
    expect(wrapper.find('[data-exemplo]').exists()).toBe(true);
    expect(wrapper.find('[data-ideias]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('points the query to the draft as soon as it exists, so F5 continues it', async () => {
    const wrapper = await montar({ query: { modelo: 'support' } });
    store.state['autonomiaBuildThreads/getThread'] = { id: 7, agent_id: 90 };
    await flushPromises();

    expect(router.replace).toHaveBeenCalledWith({ query: { agente: '90' } });
    wrapper.unmount();
  });

  it('on the computer, the phone turns into the test when the conversation closes', async () => {
    const wrapper = await montar();
    const campo = wrapper
      .get('[data-conversa]')
      .element.closest('section')
      .querySelector('textarea');
    campo.focus();
    conversaFecha();
    await flushPromises();

    expect(router.replace).toHaveBeenCalledWith({
      query: { agente: '90', etapa: 'confira' },
    });
    expect(wrapper.find('[data-confira]').exists()).toBe(true);
    expect(wrapper.find('[data-exemplo]').exists()).toBe(false);
    // A conversa continua ao lado, e o foco fica no campo (mesma tela).
    expect(wrapper.find('[data-conversa]').exists()).toBe(true);
    expect(document.activeElement).toBe(campo);
    expect(etapaAtual()).toBe('AGENTS.JORNADA.CRIAR.ETAPAS.CONFIRA');
    wrapper.unmount();
  });

  it('on the phone, closing does not switch screens: the bar offers to see the answers', async () => {
    const wrapper = await montar({ celular: true });
    expect(wrapper.find('[data-ver-exemplo]').exists()).toBe(true);
    conversaFecha();
    await flushPromises();

    expect(wrapper.find('[data-confira]').exists()).toBe(false);
    const verComo = wrapper.get('[data-ver-como]');
    expect(verComo.classes()).toContain('min-h-14');
    await verComo.trigger('click');
    await flushPromises();

    expect(router.push).toHaveBeenCalledWith({
      query: { agente: '90', etapa: 'confira' },
    });
    expect(wrapper.find('[data-confira]').exists()).toBe(true);
    expect(wrapper.find('[data-conversa]').exists()).toBe(false);
    expect(wrapper.find('[data-voltar-conversa]').exists()).toBe(true);
    wrapper.unmount();
  });

  // Jornada inteira (teste, folha, começar, Pronto): mais passos que os outros casos.
  it('starts answering only after one test answer, then activates and connects, and shows Pronto', async () => {
    const wrapper = await montar();
    conversaFecha();
    await flushPromises();
    expect(wrapper.find('[data-comecar]').exists()).toBe(false);

    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();
    const comecar = wrapper.get('[data-comecar] button');
    expect(comecar.text()).toBe('AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_NO');
    await comecar.trigger('click');
    await flushPromises();

    expect(rota.atual.query.etapa).toBe('comece');
    corpo().querySelector('[role="dialog"] [data-comecar]').click();
    await flushPromises();

    const daCriacao = passo =>
      !passo.startsWith('autonomiaBuildThreads') &&
      !passo.startsWith('autonomiaSources');
    expect(ordem.filter(daCriacao)).toEqual([
      'autonomiaAgents/test',
      'autonomiaAgents/update',
      'post:90:10',
    ]);
    expect(rota.atual.query.etapa).toBe('pronto');
    expect(wrapper.get('h1').text()).toBe('AGENTS.JORNADA.CRIAR.PRONTO.TITULO');
    expect(document.activeElement.id).toBe('pronto-titulo');
    expect(wrapper.get('[data-celular]').text()).toContain(
      'Abrimos sim, das 9h às 13h.'
    );
    wrapper.unmount();
  }, 15000);

  it('keeps the drawer open with "nothing changed" when starting fails, and reloads the inboxes', async () => {
    canaisApi.connect.mockRejectedValue(
      Object.assign(new Error('500'), { response: { status: 500 } })
    );
    const wrapper = await montar({ query: { agente: '90', etapa: 'confira' } });
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();
    await wrapper.get('[data-comecar] button').trigger('click');
    await flushPromises();
    jornada.canaisOcupados.mockClear();
    corpo().querySelector('[role="dialog"] [data-comecar]').click();
    await flushPromises();

    expect(rota.atual.query.etapa).toBe('comece');
    expect(corpo().querySelector('[data-erro-comecar]').textContent).toContain(
      'AGENTS.JORNADA.ERRO.COMECAR_ATENDER_GARANTIA'
    );
    expect(jornada.canaisOcupados).toHaveBeenCalledTimes(1);
    // Desfez o "Atendendo": o agente volta ao que era.
    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaAgents/update', {
      id: 90,
      enabled: false,
      status: 'draft',
    });
    wrapper.unmount();
  });

  it('continues a draft with instruction straight in Confira, without opening a thread', async () => {
    const wrapper = await montar({ query: { agente: '90' } });

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 90);
    expect(ordem).not.toContain('autonomiaBuildThreads/start');
    expect(wrapper.find('[data-confira]').exists()).toBe(true);
    expect(wrapper.text()).toContain('AGENTS.JORNADA.CRIAR.CONTE.CONTINUAR');
    wrapper.unmount();
  });

  // O registro na store pode estar velho (has_instruction false) enquanto o Construtor escreve: a
  // criação não decide por ele; pergunta e quem diz "ainda não sabe o suficiente" é o 422.
  it('asks the test even with a stale draft record, and shows "not enough yet" on a 422', async () => {
    prepararStore({
      agente: { ...AGENTE, has_instruction: false },
      teste: Object.assign(new Error('422'), { response: { status: 422 } }),
    });
    const wrapper = await montar({ query: { modelo: 'support' } });
    conversaFecha();
    store.state['autonomiaAgents/getRecords'] = [
      { ...AGENTE, has_instruction: false },
    ];
    await flushPromises();
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();

    expect(ordem).toContain('autonomiaAgents/test');
    expect(wrapper.get('[data-erro-teste]').text()).toContain(
      'AGENTS.JORNADA.CRIAR.CONFIRA.INCOMPLETO'
    );
    expect(wrapper.find('[data-comecar]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('F5 on Comece without a test answer falls back to Confira', async () => {
    const wrapper = await montar({ query: { agente: '90', etapa: 'comece' } });
    expect(corpo().querySelector('[role="dialog"]')).toBeNull();
    expect(wrapper.find('[data-confira]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('sends an agent that already answers to its own page', async () => {
    prepararStore({ agente: { ...AGENTE, status: 'active', enabled: true } });
    const wrapper = await montar({ query: { agente: '90' } });
    expect(router.replace).toHaveBeenCalledWith({
      name: 'autonomia_agent_panel',
      params: { agentId: 90 },
    });
    wrapper.unmount();
  });

  it('F5 on Pronto shows where the agent answers, from the inbox reading', async () => {
    prepararStore({ agente: { ...AGENTE, status: 'active', enabled: true } });
    jornada.canaisOcupados.mockResolvedValue({
      data: {
        payload: [
          {
            ...L2[0],
            occupied_by: { kind: 'agent', agent_id: 90, agent_name: 'Duda' },
          },
        ],
      },
    });
    const wrapper = await montar({ query: { agente: '90', etapa: 'pronto' } });
    expect(wrapper.get('h1').text()).toBe('AGENTS.JORNADA.CRIAR.PRONTO.TITULO');
    expect(wrapper.find('[data-celular]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('shows a card with one way out when the draft cannot be opened', async () => {
    prepararStore({ falhaShow: true });
    const wrapper = await montar({ query: { agente: '90' } });
    const erro = wrapper.get('[data-erro-abrir]');
    expect(erro.text()).toContain('AGENTS.JORNADA.CRIAR.ERRO_ABRIR');
    wrapper.unmount();
  });

  it('asks before leaving a draft, and says it stays as Not finished', async () => {
    const wrapper = await montar({ query: { agente: '90' } });
    HTMLDialogElement.prototype.showModal ||= function abrir() {
      this.open = true;
    };
    HTMLDialogElement.prototype.close ||= function fechar() {
      this.open = false;
    };
    await wrapper.get('[data-voltar-lista]').trigger('click');
    expect(router.push).not.toHaveBeenCalled();
    expect(corpo().textContent).toContain('AGENTS.JORNADA.CRIAR.SAIR.FICAR');
    wrapper.unmount();
  });

  it('leaves at once when nothing was created yet', async () => {
    const wrapper = await montar();
    await wrapper.get('[data-voltar-lista]').trigger('click');
    expect(router.push).toHaveBeenCalledWith({
      name: 'autonomia_agents_index',
    });
    expect(alerta).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('"Not now" keeps the draft and says so', async () => {
    const wrapper = await montar({ query: { agente: '90' } });
    await wrapper.get('[data-depois]').trigger('click');
    expect(router.push).toHaveBeenCalledWith({
      name: 'autonomia_agents_index',
    });
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.CRIAR.SAIR.FEITO');
    wrapper.unmount();
    // A conversa estava fechada: nada de fechar de novo no servidor.
    expect(ordem).not.toContain('autonomiaBuildThreads/completeMaterials');
  });

  // Com contexto: a pergunta e a resposta vão para o campo da conversa, e a pessoa completa o porquê.
  it('"Wrong answer?" fills the conversation field with the question and the answer (and opens it on the phone)', async () => {
    const wrapper = await montar({
      query: { agente: '90', etapa: 'confira' },
      celular: true,
    });
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();
    await wrapper.get('[data-respondeu-errado]').trigger('click');
    await flushPromises();

    expect(ordem).not.toContain('autonomiaBuildThreads/start');
    expect(rota.atual.query.etapa).toBe('conte');
    expect(secaoDaConversa(wrapper).get('textarea').element.value).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.RESPONDEU_ERRADO_RASCUNHO'
    );
    wrapper.unmount();
  });

  it('gives the typed text back to the field when the Builder is still busy (409)', async () => {
    const wrapper = await montar();
    store.state['autonomiaBuildThreads/getStatus'] = 'open';
    await flushPromises();
    falharAcao('autonomiaBuildThreads/send', conflito());
    const secao = secaoDaConversa(wrapper);
    await secao.get('textarea').setValue('Loja de roupas');
    await secao.get('form').trigger('submit');
    await flushPromises();

    expect(ordem).toContain('autonomiaBuildThreads/send');
    expect(secao.get('textarea').element.value).toBe('Loja de roupas');
    expect(secao.get('[data-espere]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('F5 on a draft keeps the model: the test questions come from the agent type', async () => {
    prepararStore({ agente: { ...AGENTE, agent_type: 'sdr' } });
    const wrapper = await montar({ query: { agente: '90' } });
    const perguntas = wrapper.get('[data-perguntas]').findAll('button');
    expect(perguntas[0].text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.PEDIDO'
    );
    wrapper.unmount();
  });

  it('says in one sentence that nothing changed when an internal agent cannot start', async () => {
    prepararStore({ agente: { ...AGENTE, actuation: 'internal' } });
    const wrapper = await montar({ query: { agente: '90' } });
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();
    falharAcao('autonomiaAgents/update', new Error('500'));
    await wrapper.get('[data-comecar] button').trigger('click');
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith(
      'AGENTS.JORNADA.CRIAR.COMECE.ERRO_INTERNO'
    );
    wrapper.unmount();
  });

  it('reads the inboxes again when Comece opens and when the window gets focus back', async () => {
    const wrapper = await montar({ query: { agente: '90' } });
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();
    jornada.canaisOcupados.mockClear();
    await wrapper.get('[data-comecar] button').trigger('click');
    await flushPromises();
    expect(jornada.canaisOcupados).toHaveBeenCalledTimes(1);

    window.dispatchEvent(new Event('focus'));
    await flushPromises();
    expect(jornada.canaisOcupados).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('a photo without text in the test goes with a default text and shows in the customer bubble', async () => {
    // O jsdom não tem prévia de arquivo; o campo pede uma para mostrar a foto antes de mandar.
    const { createObjectURL, revokeObjectURL } = URL;
    URL.createObjectURL = () => 'blob:x';
    URL.revokeObjectURL = () => {};
    const wrapper = await montar({ query: { agente: '90' } });
    const confira = wrapper.get('[data-confira]');
    const seletor = confira.get('input[type="file"]');
    Object.defineProperty(seletor.element, 'files', {
      value: [new File(['x'], 'vitrine.png', { type: 'image/png' })],
    });
    await seletor.trigger('change');
    await confira.get('form').trigger('submit');

    await vi.waitFor(() =>
      expect(store.dispatch).toHaveBeenCalledWith(
        'autonomiaAgents/test',
        expect.objectContaining({
          message: 'AGENTS.JORNADA.CRIAR.CONFIRA.FOTO',
          images: [expect.stringContaining('data:image/png')],
        })
      )
    );
    await flushPromises();
    expect(wrapper.find('[data-balao="cliente"] img').exists()).toBe(true);
    wrapper.unmount();
    URL.createObjectURL = createObjectURL;
    URL.revokeObjectURL = revokeObjectURL;
  });

  it('clears the test and says "Updated" when the Builder changes the agent again', async () => {
    const wrapper = await montar();
    conversaFecha();
    await flushPromises();
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();

    store.state['autonomiaBuildThreads/getPhase'] = 'interviewing';
    await nextTick();
    store.state['autonomiaBuildThreads/getPhase'] = 'reviewing';
    await flushPromises();

    expect(wrapper.find('[data-atualizado]').exists()).toBe(true);
    expect(wrapper.findAll('[data-balao]')).toHaveLength(0);
    wrapper.unmount();
  });

  it('without the inbox reading, offers the free inboxes of the agent', async () => {
    jornada.canaisOcupados.mockRejectedValue(new Error('404'));
    canaisApi.get.mockResolvedValue({
      data: {
        payload: [],
        eligible_inboxes: [
          { id: 12, name: 'Chat do site', channel_type: 'Channel::WebWidget' },
        ],
      },
    });
    const wrapper = await montar({ query: { agente: '90' } });
    await flushPromises();
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();

    expect(canaisApi.get).toHaveBeenCalledWith(90);
    expect(wrapper.get('[data-comecar] button').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_NO'
    );
    await wrapper.get('[data-comecar] button').trigger('click');
    await flushPromises();
    expect(corpo().textContent).toContain(
      'AGENTS.JORNADA.ONDE_QUANDO.SEM_LEITURA'
    );
    wrapper.unmount();
  });

  it('with no inbox at all, the button becomes "connect a channel"', async () => {
    jornada.canaisOcupados.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await montar({ query: { agente: '90' } });
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-comecar]').exists()).toBe(false);
    expect(wrapper.get('[data-conectar]').attributes('href')).toBe(
      '/app/settings_inbox_new'
    );
    wrapper.unmount();
  });

  it('an internal agent starts answering without choosing an inbox', async () => {
    prepararStore({ agente: { ...AGENTE, actuation: 'internal' } });
    const wrapper = await montar({ query: { agente: '90' } });
    await wrapper.get('[data-perguntas] button').trigger('click');
    await flushPromises();
    await wrapper.get('[data-comecar] button').trigger('click');
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 90,
      enabled: true,
      status: 'active',
    });
    expect(canaisApi.connect).not.toHaveBeenCalled();
    expect(wrapper.get('h1').text()).toBe(
      'AGENTS.JORNADA.CRIAR.PRONTO.TITULO_SEM_CANAL'
    );
    wrapper.unmount();
  });

  it('stops the Builder polling when leaving the page', async () => {
    const wrapper = await montar();
    wrapper.unmount();
    expect(store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/stopPolling'
    );
  });

  it('never renders a native select', async () => {
    const wrapper = await montar({ query: { agente: '90' } });
    expect(corpo().querySelector('select')).toBeNull();
    wrapper.unmount();
  });
});
