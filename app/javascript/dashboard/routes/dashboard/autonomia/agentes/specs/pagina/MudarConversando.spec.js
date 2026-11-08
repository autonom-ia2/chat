import { nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import MudarConversando from '../../components/pagina/MudarConversando.vue';

// T11 · Mudar conversando: a mesma conversa do Construtor (store autonomiaBuildThreads, que guarda uma
// conversa só), ideias que preenchem o campo, aviso de nome novo e poll parado ao sair.
const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  commit: vi.fn(),
  state: null,
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state?.[nome] ?? false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const imagens = vi.hoisted(() => ({ upload: vi.fn() }));
vi.mock('dashboard/api/autonomia/builderImages', () => ({ default: imagens }));
const conversas = vi.hoisted(() => ({ desfazer: vi.fn() }));
const sentry = vi.hoisted(() => ({ captureException: vi.fn() }));
vi.mock('@sentry/vue', () => sentry);
vi.mock('dashboard/api/autonomia/buildThreads', () => ({ default: conversas }));

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
const ESTADO = 'autonomiaBuildThreads/';

const AGENTE = {
  id: 7,
  name: 'Bia',
  tone: 'amigavel',
  agent_type: 'support',
  has_instruction: true,
};

const preparar = () => {
  store.state = reactive({
    [`${ESTADO}getMessages`]: [],
    [`${ESTADO}getStatus`]: null,
    [`${ESTADO}getError`]: null,
    [`${ESTADO}getUIFlags`]: { sending: false, creating: false },
    [`${ESTADO}getThread`]: null,
    [`${ESTADO}getAgent`]: null,
    [`${ESTADO}getPhase`]: null,
    [`${ESTADO}getThreadState`]: {},
  });
  store.dispatch.mockImplementation(async acao => {
    if (acao === `${ESTADO}start`) {
      store.state[`${ESTADO}getThread`] = { id: 55 };
    }
    return null;
  });
};

const montar = props =>
  mount(MudarConversando, {
    attachTo: document.body,
    props: { agente: AGENTE, ...props },
  });

const escrever = async texto => {
  const campo = no('form textarea');
  campo.value = texto;
  campo.dispatchEvent(new Event('input'));
  await nextTick();
};

const enviar = async () => {
  no('[data-enviar]').closest('form').dispatchEvent(new Event('submit'));
  await flushPromises();
};

describe('MudarConversando', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn(function abrir() {
      this.setAttribute('open', '');
    });
    HTMLDialogElement.prototype.close = vi.fn(function fechar() {
      this.removeAttribute('open');
    });
  });

  beforeEach(() => {
    store.dispatch.mockReset();
    store.commit.mockReset();
    preparar();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('starts clean: stops the old poll and resets the single conversation, without opening one', async () => {
    const wrapper = montar();
    await nextTick();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}stopPolling`);
    expect(store.commit).toHaveBeenCalledWith(`${ESTADO}RESET`);
    expect(store.dispatch).not.toHaveBeenCalledWith(
      `${ESTADO}start`,
      expect.anything()
    );
    expect(no('[data-abertura]').textContent).toContain('MUDAR_VISTA.ABERTURA');
    wrapper.unmount();
  });

  it('cleans up again when the first message comes back after leaving', async () => {
    let soltar;
    store.dispatch.mockImplementation(acao =>
      acao === `${ESTADO}start`
        ? new Promise(resolve => {
            soltar = resolve;
          })
        : Promise.resolve(null)
    );
    const wrapper = montar();
    await escrever('Mais formal');
    await enviar();
    wrapper.unmount();
    store.dispatch.mockClear();
    store.commit.mockClear();

    soltar(null);
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}stopPolling`);
    expect(store.commit).toHaveBeenCalledWith(`${ESTADO}RESET`);
  });

  it('fills the field with an idea instead of sending it', async () => {
    const wrapper = montar({ origem: 'jeito' });
    await nextTick();
    const ideias = todos('[data-ideias] button');
    expect(ideias.map(ideia => ideia.textContent.trim())).toEqual([
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.A',
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.B',
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.C',
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.D',
    ]);
    ideias[1].click();
    await nextTick();
    expect(no('form textarea').value).toBe(
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_JEITO.B'
    );
    expect(store.dispatch).not.toHaveBeenCalledWith(
      `${ESTADO}start`,
      expect.anything()
    );
    wrapper.unmount();
  });

  it('opens the conversation on the first message and continues it on the next', async () => {
    const wrapper = montar();
    await escrever('Mais formal');
    await enviar();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}start`, {
      agentId: 7,
      type: 'support',
      message: 'Mais formal',
      image_signed_ids: [],
    });

    await escrever('Sim');
    await enviar();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}send`, {
      threadId: 55,
      content: 'Sim',
      extra: { image_signed_ids: [] },
    });
    wrapper.unmount();
  });

  it('shows the turns, thinking and the standard error with a retry', async () => {
    store.state[`${ESTADO}getMessages`] = [
      { role: 'user', content: 'Mudar preços' },
      { role: 'assistant', content: 'O que mudou?' },
    ];
    store.state[`${ESTADO}getStatus`] = 'processing';
    const wrapper = montar();
    await nextTick();
    expect(todos('[data-mensagem]').map(m => m.dataset.mensagem)).toEqual([
      'user',
      'assistant',
    ]);
    expect(no('[data-pensando]')).not.toBeNull();
    expect(no('[data-ideias]')).toBeNull();

    store.state[`${ESTADO}getStatus`] = 'failed';
    store.state[`${ESTADO}getError`] = 'failed';
    store.state[`${ESTADO}getThread`] = { id: 55 };
    await nextTick();
    const erro = no('[data-erro]');
    expect(erro.textContent).toContain('MUDAR_VISTA.ERRO_GARANTIA');
    erro.querySelector('button').click();
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}retry`, {
      threadId: 55,
    });
    wrapper.unmount();
  });

  it('tells the new name with a way back, and that the way of talking changed', async () => {
    const wrapper = montar();
    store.state[`${ESTADO}getAgent`] = {
      ...AGENTE,
      name: 'Rosa',
      tone: 'formal',
    };
    await nextTick();

    expect(no('[data-feito]').textContent).toContain('MUDAR_VISTA.FEITO');
    expect(no('[data-nome-novo]').textContent).toContain(
      'MUDAR_VISTA.NOME_NOVO'
    );
    expect(no('[data-jeito-novo]')).not.toBeNull();
    expect(no('[data-atualizado]')).not.toBeNull();
    no('[data-voltar-nome]').click();
    expect(wrapper.emitted('voltarNome')).toEqual([['Bia']]);
    wrapper.unmount();
  });

  // #1428 — part of the request went in and the builder still asks about the
  // rest: the screen shows what went in, with the question open below it.
  it('shows that part of the request went in while the builder still asks a question', async () => {
    const wrapper = montar();
    store.state[`${ESTADO}getMessages`] = [
      { role: 'user', content: 'Curto e melhore a saudação' },
      { role: 'assistant', content: 'Como você quer a saudação?' },
    ];
    store.state[`${ESTADO}getStatus`] = 'open';
    store.state[`${ESTADO}getPhase`] = 'interviewing';
    store.state[`${ESTADO}getThreadState`] = { parcial: true };
    store.state[`${ESTADO}getAgent`] = { ...AGENTE, tone: 'curto' };
    await nextTick();

    expect(no('[data-parcial]').textContent).toContain('MUDAR_VISTA.PARCIAL');
    expect(no('[data-feito]')).toBeNull();
    const ordem = todos('[data-parcial], [data-mensagem="assistant"]');
    expect(ordem.indexOf(no('[data-parcial]'))).toBeLessThan(
      ordem.indexOf(todos('[data-mensagem="assistant"]').pop())
    );
    expect(todos('[data-mensagem="assistant"]').pop().textContent).toContain(
      'Como você quer a saudação?'
    );
    wrapper.unmount();
  });

  // #1428 — "também mudei isto, que você não pediu": tudo entrou, então é FEITO, com o aviso na conversa acima.
  it('shows FEITO after the notice when everything went in and the builder only informs', async () => {
    const wrapper = montar();
    store.state[`${ESTADO}getMessages`] = [
      { role: 'user', content: 'Responda curto' },
      { role: 'assistant', content: 'Também mudei isto, que você não pediu.' },
    ];
    store.state[`${ESTADO}getStatus`] = 'ready';
    store.state[`${ESTADO}getPhase`] = 'reviewing';
    store.state[`${ESTADO}getThreadState`] = { parcial: false };
    store.state[`${ESTADO}getAgent`] = { ...AGENTE, tone: 'curto' };
    await nextTick();

    expect(no('[data-parcial]')).toBeNull();
    const cartao = no('[data-feito]');
    const aviso = todos('[data-mensagem="assistant"]').pop();
    expect(aviso.textContent).toContain('que você não pediu');
    const ordem = todos('[data-feito], [data-mensagem="assistant"]');
    expect(ordem.indexOf(aviso)).toBeLessThan(ordem.indexOf(cartao));
    wrapper.unmount();
  });

  // #1428 (parte 3, piloto) — com o resultado do servidor, o cartão pedido por pedido no lugar do FEITO.
  describe('with the result of the adjustment (pilot)', () => {
    const RESULTADO = {
      itens: [
        { estado: 'aplicado', texto: 'Respostas curtas.' },
        { estado: 'nao_aplicado', texto: 'preço com a equipe' },
      ],
      faltou_fora: false,
      conferido: true,
      desfeito: false,
      desfeito_sozinho: false,
      pode_desfazer: true,
    };

    const comResultado = async (resultado = RESULTADO, agente = AGENTE) => {
      const wrapper = montar();
      store.state[`${ESTADO}getThread`] = { id: 55 };
      store.state[`${ESTADO}getMessages`] = [
        { role: 'user', content: 'Curto e preço com a equipe' },
        { role: 'assistant', content: 'Qual equipe?' },
      ];
      store.state[`${ESTADO}getStatus`] = 'open';
      store.state[`${ESTADO}getPhase`] = 'interviewing';
      store.state[`${ESTADO}getThreadState`] = { parcial: true, resultado };
      store.state[`${ESTADO}getAgent`] = agente && { ...agente, tone: 'curto' };
      await nextTick();
      return wrapper;
    };

    it('shows the card before the open question, and Pronto stays plain while something is missing', async () => {
      const wrapper = await comResultado();

      expect(no('[data-feito]')).toBeNull();
      expect(no('[data-parcial]')).toBeNull();
      const cartao = no('[data-conferido]');
      const pergunta = todos('[data-mensagem="assistant"]').pop();
      const ordem = todos('[data-conferido], [data-mensagem="assistant"]');
      expect(ordem.indexOf(cartao)).toBeLessThan(ordem.indexOf(pergunta));
      expect(todos('[data-item]').map(item => item.dataset.item)).toEqual([
        'aplicado',
        'nao_aplicado',
      ]);
      expect(no('[data-pronto]').className).not.toContain('bg-n-blue-11');
      wrapper.unmount();
    });

    // #1428 (entrega B) — a prova chega depois do cartão: a página pede à store que acompanhe só ela.
    it('follows the proof while it is pending, and only then', async () => {
      const wrapper = await comResultado({
        ...RESULTADO,
        prova: { status: 'pendente', total: 3 },
      });
      const acompanhar = () =>
        store.dispatch.mock.calls.filter(
          ([acao]) => acao === `${ESTADO}acompanharProva`
        );

      expect(acompanhar()).toEqual([
        [`${ESTADO}acompanharProva`, { threadId: 55 }],
      ]);
      expect(no('[data-prova]').dataset.status).toBe('pendente');

      store.state[`${ESTADO}getThreadState`] = {
        resultado: {
          ...RESULTADO,
          prova: { status: 'pronta', ok: 3, total: 3, perguntas: [] },
        },
      };
      await nextTick();
      expect(acompanhar()).toHaveLength(1);
      wrapper.unmount();
    });

    it('makes Pronto primary when everything asked went in', async () => {
      const wrapper = await comResultado({
        ...RESULTADO,
        itens: [
          { estado: 'aplicado', texto: 'Curto.' },
          { estado: 'sem_pedido', texto: 'Saudação nova' },
        ],
      });

      expect(no('[data-pronto]').className).toContain('bg-n-blue-11');
      wrapper.unmount();
    });

    it('undoes through the store and starts the test phone over', async () => {
      // Sem o agente relido (a leitura dele pode falhar), o celular recomeça pelo próprio Desfazer.
      const wrapper = await comResultado(RESULTADO, null);
      expect(no('[data-atualizado]')).toBeNull();

      no('[data-desfazer]').click();
      await flushPromises();

      expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}desfazerAjuste`, {
        threadId: 55,
      });
      expect(no('[data-atualizado]')).not.toBeNull();
      expect(no('[data-erro-desfazer]')).toBeNull();
      wrapper.unmount();
    });

    it('after a 409 says the agent changed and hides the undo', async () => {
      const wrapper = await comResultado();
      store.dispatch.mockImplementation(async acao => {
        if (acao === `${ESTADO}desfazerAjuste`) {
          throw Object.assign(new Error('conflito'), {
            response: { status: 409 },
          });
        }
        return null;
      });

      no('[data-desfazer]').click();
      await flushPromises();

      expect(no('[data-erro-desfazer]').textContent).toContain(
        'CONFERIDO.MUDOU_DEPOIS'
      );
      expect(no('[data-desfazer]')).toBeNull();
      wrapper.unmount();
    });
  });

  // #1428 (parte 3) — a faixa "Última mudança" na tela nova: o direito de desfazer vem do servidor, no
  // agente, mesmo depois de recarregar a página.
  describe('last change strip (pilot)', () => {
    const ULTIMA = { thread_id: 41, linhas: ['Respostas curtas'] };
    const comUltima = (
      agente = { ...AGENTE, ultima_mudanca_desfazivel: ULTIMA }
    ) => montar({ agente });

    beforeEach(() => {
      conversas.desfazer.mockReset();
    });

    it('shows the last change above the new conversation, and nothing without it', async () => {
      const wrapper = comUltima();
      await nextTick();
      expect(no('[data-ultima-mudanca]').textContent).toContain(
        'CONFERIDO.ULTIMA_MUDANCA'
      );
      wrapper.unmount();

      const semUltima = montar();
      await nextTick();
      expect(no('[data-ultima-mudanca]')).toBeNull();
      semUltima.unmount();
    });

    it('goes away when the agent changes, while thinking and behind the result card', async () => {
      const wrapper = comUltima();
      await nextTick();
      await wrapper.setProps({ agente: { ...AGENTE } });
      expect(no('[data-ultima-mudanca]')).toBeNull();

      await wrapper.setProps({
        agente: { ...AGENTE, ultima_mudanca_desfazivel: ULTIMA },
      });
      store.state[`${ESTADO}getStatus`] = 'processing';
      await nextTick();
      expect(no('[data-ultima-mudanca]')).toBeNull();

      store.state[`${ESTADO}getStatus`] = 'ready';
      store.state[`${ESTADO}getThreadState`] = {
        resultado: { itens: [], conferido: true, pode_desfazer: true },
      };
      await nextTick();
      expect(no('[data-ultima-mudanca]')).toBeNull();
      wrapper.unmount();
    });

    it('stays after a question in the same conversation (no result card)', async () => {
      const wrapper = comUltima();
      store.state[`${ESTADO}getMessages`] = [
        { role: 'user', content: 'O que ele faz?' },
        { role: 'assistant', content: 'Ele atende os clientes.' },
      ];
      store.state[`${ESTADO}getStatus`] = 'open';
      await nextTick();
      expect(no('[data-ultima-mudanca]')).not.toBeNull();
      wrapper.unmount();
    });

    it('undoes by the thread the server named, re-reads the agent and restarts the phone', async () => {
      conversas.desfazer.mockResolvedValue({ data: {} });
      const wrapper = comUltima();
      await nextTick();
      expect(no('[data-atualizado]')).toBeNull();

      no('[data-desfazer-ultima]').click();
      await flushPromises();

      expect(conversas.desfazer).toHaveBeenCalledWith(41);
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 7);
      expect(no('[data-ultima-desfeita]').textContent).toContain(
        'CONFERIDO.DESFEITO'
      );
      expect(no('[data-ultima-mudanca]')).toBeNull();
      expect(no('[data-atualizado]')).not.toBeNull();
      wrapper.unmount();
    });

    it('after a 409 says the agent changed and hides the undo', async () => {
      conversas.desfazer.mockRejectedValue({ response: { status: 409 } });
      const wrapper = comUltima();
      await nextTick();

      no('[data-desfazer-ultima]').click();
      await flushPromises();

      expect(no('[data-erro-desfazer]').textContent).toContain(
        'CONFERIDO.MUDOU_DEPOIS'
      );
      expect(no('[data-desfazer-ultima]')).toBeNull();
      expect(no('[data-ultima-desfeita]')).toBeNull();
      wrapper.unmount();
    });
  });

  // #1428 (parte 3, F3): o Desfazer cancelou o pedido em voo desta conversa.
  it('says the request was canceled by the undo, without a retry', async () => {
    const wrapper = montar();
    store.state[`${ESTADO}getThread`] = { id: 55 };
    store.state[`${ESTADO}getStatus`] = 'failed';
    store.state[`${ESTADO}getError`] = 'failed';
    store.state[`${ESTADO}getThreadState`] = {
      error: 'superada_pelo_desfazer',
    };
    await nextTick();

    const erro = no('[data-erro]');
    expect(erro.textContent).toContain('MUDAR_VISTA.CANCELADO_PELO_DESFAZER');
    expect(erro.textContent).not.toContain('MUDAR_VISTA.ERRO_GARANTIA');
    expect(erro.querySelector('button')).toBeNull();
    wrapper.unmount();
  });

  it('says nothing about the name when it did not change', async () => {
    const wrapper = montar();
    store.state[`${ESTADO}getAgent`] = { ...AGENTE };
    await nextTick();
    expect(no('[data-feito]')).not.toBeNull();
    expect(no('[data-nome-novo]')).toBeNull();
    expect(no('[data-jeito-novo]')).toBeNull();
    wrapper.unmount();
  });

  it('comes from the test with the question and the answer in the field and on the phone', async () => {
    const wrapper = montar({
      origem: 'teste',
      testeInicial: { pergunta: 'Vocês abrem no sábado?', resposta: 'Abrimos' },
    });
    await nextTick();
    expect(no('form textarea').value).toBe(
      'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.RASCUNHO_ERRADO'
    );
    expect(no('[data-ideias]')).toBeNull();
    expect(todos('[data-balao]').length).toBeGreaterThan(0);
    wrapper.unmount();
  });

  it('asks before leaving in the middle of a conversation', async () => {
    store.state[`${ESTADO}getMessages`] = [{ role: 'user', content: 'Oi' }];
    const wrapper = montar();
    await nextTick();
    no('[data-voltar]').click();
    await nextTick();
    expect(wrapper.emitted('sair')).toBeUndefined();
    expect(document.querySelector('dialog').textContent).toContain(
      'MUDAR_VISTA.SAIR_TITULO'
    );
    no('dialog [data-confirmar]').click();
    await flushPromises();
    expect(wrapper.emitted('sair')).toHaveLength(1);
    wrapper.unmount();
  });

  it('leaves right away when nothing was said, and stops the poll on the way out', async () => {
    const wrapper = montar();
    await nextTick();
    no('[data-pronto]').click();
    expect(wrapper.emitted('sair')).toHaveLength(1);
    store.dispatch.mockClear();
    store.commit.mockClear();
    wrapper.unmount();
    expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}stopPolling`);
    expect(store.commit).toHaveBeenCalledWith(`${ESTADO}RESET`);
  });

  // #1850 — enquanto o cartão ⚠ do turno está na tela, a última bolha só pergunta (`pergunta_curta` do cartão). A conversa
  // guarda a pergunta inteira, que volta a aparecer quando o cartão sai (turno seguinte) ou depois do Desfazer.
  describe('open question under the ⚠ card', () => {
    const INTEIRA =
      'Não consegui aplicar: preço passa para a equipe. Pode me dizer de outro jeito o que você quer?';
    const CURTA = 'Pode me dizer de outro jeito o que você quer?';
    const CARTAO = {
      itens: [{ estado: 'nao_aplicado', texto: 'preço passa para a equipe' }],
      conferido: true,
      pode_desfazer: true,
      pergunta_curta: CURTA,
    };
    const comCartao = resultado => {
      store.state[`${ESTADO}getThread`] = { id: 55 };
      store.state[`${ESTADO}getPhase`] = 'interviewing';
      store.state[`${ESTADO}getMessages`] = [
        { role: 'user', content: 'Responda curto e preço passa para a equipe' },
        { role: 'assistant', content: INTEIRA },
      ];
      store.state[`${ESTADO}getThreadState`] = {
        next_question: INTEIRA,
        ...(resultado ? { resultado } : {}),
      };
    };
    const ultimaBolha = () =>
      todos('[data-conversa] [data-mensagem="assistant"]').at(-1).textContent;

    it('shows only the question while the card shows what was not applied', async () => {
      comCartao(CARTAO);
      const wrapper = montar();
      await nextTick();

      expect(ultimaBolha()).toContain(CURTA);
      expect(ultimaBolha()).not.toContain('Não consegui aplicar');
      wrapper.unmount();
    });

    it('shows the whole question once the card is gone or undone', async () => {
      comCartao(null);
      const wrapper = montar();
      await nextTick();
      expect(ultimaBolha()).toContain(INTEIRA);

      store.state[`${ESTADO}getThreadState`] = {
        next_question: INTEIRA,
        resultado: { ...CARTAO, desfeito: true },
      };
      await nextTick();
      expect(ultimaBolha()).toContain(INTEIRA);
      wrapper.unmount();
    });

    it('keeps the whole text when the last bubble is not the open question', async () => {
      comCartao(CARTAO);
      store.state[`${ESTADO}getThreadState`] = {
        next_question: 'Outra pergunta',
        resultado: CARTAO,
      };
      const wrapper = montar();
      await nextTick();
      expect(ultimaBolha()).toContain(INTEIRA);
      wrapper.unmount();
    });
  });

  // #1428 (entrega C) — as respostas prontas da pergunta aberta: tocar é o mesmo que escrever e mandar.
  describe('ready answers under the open question', () => {
    const OPCOES = ['Passar para a equipe', 'Não falar de preço'];

    const PERGUNTA = 'Que preço ele deve dizer?';
    const comPergunta = (
      estado = { next_question: PERGUNTA, opcoes_de_resposta: OPCOES }
    ) => {
      store.state[`${ESTADO}getThread`] = { id: 55 };
      store.state[`${ESTADO}getPhase`] = 'interviewing';
      store.state[`${ESTADO}getMessages`] = [
        { role: 'user', content: 'Fale do preço' },
        { role: 'assistant', content: PERGUNTA },
      ];
      store.state[`${ESTADO}getThreadState`] = estado;
    };

    it('shows them as real buttons in a labelled group, right after the question and out of the live region', async () => {
      comPergunta();
      const wrapper = montar();
      await nextTick();

      const grupo = no('[data-opcoes]');
      expect(grupo.getAttribute('role')).toBe('group');
      expect(grupo.getAttribute('aria-label')).toBe(
        'AGENTS.JORNADA.PAGINA.MUDAR_VISTA.OPCOES_ROTULO'
      );
      const botoes = todos('[data-opcoes] button');
      expect(botoes.map(botao => botao.textContent.trim())).toEqual(OPCOES);
      expect(botoes.every(botao => botao.type === 'button')).toBe(true);
      expect(botoes[0].className).toContain('min-h-11');
      expect(grupo.closest('[aria-live]')).toBeNull();
      expect(grupo.previousElementSibling.matches('[data-conversa]')).toBe(
        true
      );
      expect(
        todos('[data-conversa] [data-mensagem]').at(-1).dataset.mensagem
      ).toBe('assistant');
      wrapper.unmount();
    });

    it('sends the tapped answer as the owner message and keeps the draft', async () => {
      comPergunta();
      const wrapper = montar();
      await escrever('rascunho meu');

      todos('[data-opcoes] button')[1].click();
      await flushPromises();

      expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}send`, {
        threadId: 55,
        content: 'Não falar de preço',
        extra: { image_signed_ids: [] },
      });
      expect(no('form textarea').value).toBe('rascunho meu');
      expect(document.activeElement).toBe(no('form textarea'));
      wrapper.unmount();
    });

    it('does not show them when the turn is not an open question, nor after the undo', async () => {
      comPergunta();
      store.state[`${ESTADO}getPhase`] = 'reviewing';
      const wrapper = montar();
      await nextTick();
      expect(no('[data-opcoes]')).toBeNull();

      store.state[`${ESTADO}getPhase`] = 'interviewing';
      store.state[`${ESTADO}getThreadState`] = {
        next_question: PERGUNTA,
        opcoes_de_resposta: OPCOES,
        resultado: { itens: [], desfeito: true },
      };
      await nextTick();
      expect(no('[data-opcoes]')).toBeNull();
      wrapper.unmount();
    });

    it('only shows them under the exact question the server sent them with', async () => {
      comPergunta({
        next_question: 'Outra pergunta',
        opcoes_de_resposta: OPCOES,
      });
      const wrapper = montar();
      await nextTick();
      expect(no('[data-opcoes]')).toBeNull();

      store.state[`${ESTADO}getThreadState`] = {
        next_question: PERGUNTA,
        opcoes_de_resposta: OPCOES,
      };
      await nextTick();
      expect(no('[data-opcoes]')).not.toBeNull();
      wrapper.unmount();
    });

    it('lets a long answer without spaces wrap inside the button', async () => {
      comPergunta();
      const wrapper = montar();
      await nextTick();

      expect(todos('[data-opcoes] button')[0].className).toContain(
        'break-words'
      );
      wrapper.unmount();
    });

    it('goes away after the undo by the last change strip, and the conversation is read again', async () => {
      conversas.desfazer.mockResolvedValue({ data: {} });
      comPergunta();
      const wrapper = montar({
        agente: {
          ...AGENTE,
          ultima_mudanca_desfazivel: { thread_id: 41, linhas: ['Curtas'] },
        },
      });
      await nextTick();
      expect(no('[data-opcoes]')).not.toBeNull();

      no('[data-desfazer-ultima]').click();
      await flushPromises();

      expect(conversas.desfazer).toHaveBeenCalledWith(41);
      expect(store.dispatch).toHaveBeenCalledWith(`${ESTADO}fetch`, {
        threadId: 55,
      });
      expect(no('[data-opcoes]')).toBeNull();
      wrapper.unmount();
    });

    it('shows at most four', async () => {
      comPergunta({
        next_question: PERGUNTA,
        opcoes_de_resposta: ['A', 'B', 'C', 'D', 'E'],
      });
      const wrapper = montar();
      await nextTick();

      expect(todos('[data-opcoes] button')).toHaveLength(4);
      wrapper.unmount();
    });

    it('hides them once the owner answered, while thinking, and without options', async () => {
      comPergunta();
      const wrapper = montar();
      await nextTick();
      expect(no('[data-opcoes]')).not.toBeNull();

      store.state[`${ESTADO}getUIFlags`] = { sending: true, creating: false };
      await nextTick();
      expect(no('[data-opcoes]')).toBeNull();

      store.state[`${ESTADO}getUIFlags`] = { sending: false, creating: false };
      store.state[`${ESTADO}getMessages`] = [
        ...store.state[`${ESTADO}getMessages`],
        { role: 'user', content: 'Não falar de preço' },
      ];
      await nextTick();
      expect(no('[data-opcoes]')).toBeNull();

      comPergunta({});
      await nextTick();
      expect(no('[data-opcoes]')).toBeNull();
      wrapper.unmount();
    });

    it('reports a failed re-read after the undo by the strip, and the answers still go away', async () => {
      conversas.desfazer.mockResolvedValue({ data: {} });
      const falha = new Error('rede');
      store.dispatch.mockImplementation(async acao => {
        if (acao === `${ESTADO}fetch`) throw falha;
        return null;
      });
      sentry.captureException.mockClear();
      comPergunta();
      const wrapper = montar({
        agente: {
          ...AGENTE,
          ultima_mudanca_desfazivel: { thread_id: 41, linhas: ['Curtas'] },
        },
      });
      await nextTick();

      no('[data-desfazer-ultima]').click();
      await flushPromises();

      expect(sentry.captureException).toHaveBeenCalledWith(falha);
      expect(no('[data-opcoes]')).toBeNull();
      expect(no('[data-ultima-desfeita]')).not.toBeNull();
      wrapper.unmount();
    });
  });
});
