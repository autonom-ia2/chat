import { defineComponent, h, nextTick, watch } from 'vue';
import { createStore } from 'vuex';
import { mount } from '@vue/test-utils';
import MessagesView from 'dashboard/components/widgets/conversation/MessagesView.vue';
import ConversationView from 'dashboard/routes/dashboard/conversation/ConversationView.vue';
import conversas from 'dashboard/store/modules/conversations';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { mensagemDestacada } from '../destaqueDaCitada';
import { TETO_DE_PAGINAS } from '../rolagemDaPele';

// A tela da conversa (MessagesView, do Chatwoot) com a pele (#1702): os métodos novos
// rodam sobre um "this" de mentira, sem montar a tela inteira.
const { methods, computed: calculados } = MessagesView;

const daLoja = (id, tipo, criadaEm) => ({
  id,
  message_type: tipo,
  created_at: criadaEm,
  content_attributes: {},
});

const contexto = ({ mensagens, todasCarregadas = false, maisAntigas = [] }) => {
  const painel = document.createElement('ul');
  document.body.appendChild(painel);
  const ctx = {
    pele: 'whatsapp',
    currentChat: {
      id: 9,
      dataFetched: true,
      agent_last_seen_at: 1000,
      messages: mensagens,
    },
    listLoadingStatus: todasCarregadas,
    conversationPanel: painel,
    naoLidasDaPele: null,
    citadaPendente: null,
    ultimaDaPele: null,
    isProgrammaticScroll: false,
    $t: chave => chave,
    $nextTick: fn => (fn ? Promise.resolve().then(fn) : Promise.resolve()),
    $store: {
      dispatch: vi.fn(async () => {
        const pagina = maisAntigas.pop();
        if (!pagina) return;
        ctx.currentChat.messages = [...pagina, ...ctx.currentChat.messages];
        if (!maisAntigas.length) ctx.listLoadingStatus = true;
      }),
    },
  };
  Object.entries(methods).forEach(([nome, metodo]) => {
    ctx[nome] = metodo.bind(ctx);
  });
  ctx.scrollToBottom = vi.fn();
  Object.defineProperty(ctx, 'faixaDaPele', {
    get: () => calculados.faixaDaPele.call(ctx),
  });
  return ctx;
};

afterEach(() => {
  document.body.innerHTML = '';
});

describe('abrir a conversa com a pele', () => {
  it('busca as páginas anteriores até achar a última lida e conta todas as não lidas', async () => {
    // 25 não lidas do cliente: a 1ª página (20) não chega à leitura.
    const pagina1 = Array.from({ length: 20 }, (_, i) =>
      daLoja(100 + i, 0, 1010 + i)
    );
    const pagina0 = [
      daLoja(90, 1, 900),
      ...Array.from({ length: 5 }, (_, i) => daLoja(95 + i, 0, 1001 + i)),
    ];
    const ctx = contexto({ mensagens: pagina1, maisAntigas: [pagina0] });

    await ctx.rolarNaPele();

    expect(ctx.$store.dispatch).toHaveBeenCalledTimes(1);
    expect(ctx.$store.dispatch).toHaveBeenCalledWith('fetchPreviousMessages', {
      conversationId: 9,
      before: 100,
    });
    expect(ctx.faixaDaPele).toMatchObject({
      primeiraNaoLida: 95,
      quantidade: 25,
    });
  });

  it('põe a faixa perto do topo', async () => {
    const ctx = contexto({
      mensagens: [daLoja(1, 0, 900), daLoja(2, 0, 1001)],
    });
    const faixa = document.createElement('li');
    faixa.setAttribute('data-faixa-nao-lidas', '');
    Object.defineProperty(faixa, 'offsetTop', { value: 900 });
    ctx.conversationPanel.appendChild(faixa);

    await ctx.rolarNaPele();

    expect(ctx.conversationPanel.scrollTop).toBe(844);
    expect(ctx.scrollToBottom).not.toHaveBeenCalled();
  });

  it('sem não lidas, vai para o fim', async () => {
    const ctx = contexto({ mensagens: [daLoja(1, 0, 900)] });
    await ctx.rolarNaPele();
    expect(ctx.faixaDaPele.primeiraNaoLida).toBeNull();
    expect(ctx.scrollToBottom).toHaveBeenCalled();
  });

  it('antes das mensagens chegarem, espera', async () => {
    const ctx = contexto({ mensagens: [] });
    ctx.currentChat.dataFetched = undefined;
    await ctx.rolarNaPele();
    expect(ctx.naoLidasDaPele).toBeNull();
  });
});

describe('mensagem nova com a pele', () => {
  const aberta = async () => {
    const ctx = contexto({ mensagens: [daLoja(1, 0, 900)] });
    await ctx.rolarNaPele();
    ctx.scrollToBottom.mockClear();
    return ctx;
  };
  const lendoLaEmCima = ctx => {
    Object.defineProperty(ctx.conversationPanel, 'scrollHeight', {
      value: 3000,
    });
    Object.defineProperty(ctx.conversationPanel, 'clientHeight', {
      value: 500,
    });
    ctx.conversationPanel.scrollTop = 1000;
  };

  it('do cliente, com o atendente lá em cima: fica onde está', async () => {
    const ctx = await aberta();
    lendoLaEmCima(ctx);
    ctx.currentChat.messages.push(daLoja(2, 0, 1100));
    await ctx.rolarNaPele();
    await Promise.resolve();
    expect(ctx.scrollToBottom).not.toHaveBeenCalled();
  });

  it('do atendente: desce', async () => {
    const ctx = await aberta();
    lendoLaEmCima(ctx);
    ctx.currentChat.messages.push(daLoja(2, 1, 1100));
    await ctx.rolarNaPele();
    await Promise.resolve();
    expect(ctx.scrollToBottom).toHaveBeenCalled();
  });
});

describe('citação com a pele', () => {
  const comMensagemNaTela = id => {
    const linha = document.createElement('div');
    linha.id = `message${id}`;
    linha.scrollIntoView = vi.fn();
    document.body.appendChild(linha);
    return linha;
  };

  it('mensagem antiga: busca as anteriores, rola até ela e destaca', async () => {
    const ctx = contexto({
      mensagens: [daLoja(50, 0, 900)],
      maisAntigas: [[daLoja(10, 0, 800)], [daLoja(30, 0, 850)]],
    });
    await ctx.rolarNaPele();
    const linha = comMensagemNaTela(10);

    await ctx.rolarNaPele(10);

    expect(ctx.$store.dispatch).toHaveBeenCalledTimes(2);
    expect(linha.scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'center',
    });
    expect(mensagemDestacada.value).toBe(10);
  });

  // #2211: a busca da lista abre a conversa com ?messageId=; o pedido chega enquanto a
  // conversa ainda abre (a faixa não está pronta) e não pode se perder.
  it('pedido que chega com a conversa ainda abrindo: abre e vai à mensagem', async () => {
    const ctx = contexto({
      mensagens: [daLoja(50, 0, 900)],
      maisAntigas: [[daLoja(10, 0, 800)], [daLoja(30, 0, 850)]],
    });
    const linha = comMensagemNaTela(10);
    const abrindo = ctx.rolarNaPele();
    await ctx.rolarNaPele(10);
    await abrindo;
    expect(linha.scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'center',
    });
    expect(mensagemDestacada.value).toBe(10);
    // Quem já abria pôs no fim; a ida à mensagem vem depois e é onde a tela fica.
    const [paraOFim = 0] = ctx.scrollToBottom.mock.invocationCallOrder;
    expect(linha.scrollIntoView.mock.invocationCallOrder[0]).toBeGreaterThan(
      paraOFim
    );
  });

  it('pedido de outra conversa não vale para esta', async () => {
    const ctx = contexto({ mensagens: [daLoja(7, 0, 900)] });
    const linha = comMensagemNaTela(7);
    ctx.citadaPendente = { conversaId: 99, id: 7 };
    await ctx.rolarNaPele();
    expect(linha.scrollIntoView).not.toHaveBeenCalled();
  });

  it('já na tela: só rola e destaca', async () => {
    const ctx = contexto({ mensagens: [daLoja(7, 0, 900)] });
    await ctx.rolarNaPele();
    const linha = comMensagemNaTela(7);
    await ctx.rolarNaPele(7);
    expect(ctx.$store.dispatch).not.toHaveBeenCalled();
    expect(linha.scrollIntoView).toHaveBeenCalled();
    expect(mensagemDestacada.value).toBe(7);
  });

  it('não achou até o teto: aviso curto', async () => {
    const avisos = vi.fn();
    emitter.on('newToastMessage', avisos);
    const ctx = contexto({
      mensagens: [daLoja(500, 0, 900)],
      maisAntigas: Array.from({ length: 20 }, (_, i) => [
        daLoja(400 - i, 0, 800),
      ]),
    });
    await ctx.rolarNaPele();

    await ctx.rolarNaPele(1);

    expect(ctx.$store.dispatch).toHaveBeenCalledTimes(TETO_DE_PAGINAS);
    expect(avisos).toHaveBeenCalledWith({
      message: 'CONVERSA_CANAL.ROLAGEM.CITADA_NAO_ENCONTRADA',
      action: null,
    });
    emitter.off('newToastMessage', avisos);
  });
});

// #2211: a conversa aberta pelo link com ?messageId= (busca do Chatwoot).
describe('abrir a conversa já indo à mensagem pedida', () => {
  const comMensagemNaTela = id => {
    const linha = document.createElement('div');
    linha.id = `message${id}`;
    linha.scrollIntoView = vi.fn();
    document.body.appendChild(linha);
    return linha;
  };
  const assentar = () =>
    new Promise(resolve => {
      setTimeout(resolve, 30);
    });
  const avisoDeNaoAchou = {
    message: 'CONVERSA_CANAL.ROLAGEM.CITADA_NAO_ENCONTRADA',
    action: null,
  };
  const aoFim = [];
  afterEach(() => aoFim.splice(0).forEach(fechar => fechar()));

  // O caminho de verdade: a loja (setActiveChat), o ConversationView e o Vue montando a
  // tela, com o watcher de currentChat do MessagesView. A tela não remonta ao trocar de
  // conversa (ConversationBox não tem key), como no painel.
  const telaDaConversa = ({ conversasDaLoja, buscarNaLoja, maisAntigas }) => {
    const acoes = buscarNaLoja ? { fetchPreviousMessages: buscarNaLoja } : {};
    const loja = createStore({
      modules: {
        conversations: {
          ...conversas,
          actions: { ...conversas.actions, ...acoes },
          state: {
            ...conversas.state,
            allConversations: conversasDaLoja,
            selectedChatId: null,
          },
        },
      },
    });
    const daLojaPorId = id =>
      loja.state.conversations.allConversations.find(c => c.id === id);
    const ctx = contexto({ mensagens: [], maisAntigas });
    Object.defineProperty(ctx, 'currentChat', {
      get: () => loja.getters.getSelectedChat || {},
    });
    ctx.$nextTick = nextTick;
    [
      'makeMessagesRead',
      'fetchAllAttachmentsFromCurrentChat',
      'fetchSuggestions',
      'fetchParticipantsForReading',
      'resetReplyEditorHeight',
    ].forEach(nome => {
      ctx[nome] = vi.fn();
    });
    // Como no MessagesView.mounted: conversa já carregada não espera o aviso de abrir.
    const TelaDaConversa = {
      mounted() {
        this.$nextTick(() => ctx.rolarNaPele());
      },
      render: () => null,
    };
    const Caixa = defineComponent({
      setup() {
        watch(
          () => loja.getters.getSelectedChat,
          (nova, antiga) =>
            MessagesView.watch.currentChat.call(ctx, nova || {}, antiga || {})
        );
        return () =>
          loja.getters.getSelectedChat?.id ? h(TelaDaConversa) : null;
      },
    });
    const tela = mount(Caixa, { global: { plugins: [loja] } });
    const avisos = vi.fn();
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, ctx.onScrollToMessage);
    emitter.on('newToastMessage', avisos);
    aoFim.push(() => {
      emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, ctx.onScrollToMessage);
      emitter.off('newToastMessage', avisos);
      tela.unmount();
    });
    // Clique na lista (sem messageId) ou no resultado da busca (com messageId).
    const abrir = (id, messageId) =>
      ConversationView.methods.setActiveChat.call({
        conversationId: String(id),
        findConversation: () => daLojaPorId(id),
        currentChat: ctx.currentChat,
        $route: { query: messageId ? { messageId } : {} },
        $store: loja,
      });
    const aberta = id =>
      vi.waitFor(() => expect(ctx.faixaDaPele?.conversaId).toBe(id), {
        timeout: 500,
      });
    return { ctx, abrir, aberta, avisos, daLojaPorId };
  };

  it('pedido que chega com a conversa ainda abrindo: vai direto à mensagem, sem pular para o fim', async () => {
    const ctx = contexto({
      mensagens: [daLoja(50, 0, 900)],
      maisAntigas: [[daLoja(10, 0, 800)], [daLoja(30, 0, 850)]],
    });
    const linha = comMensagemNaTela(10);
    const abrindo = ctx.rolarNaPele();
    await ctx.rolarNaPele(10);
    await abrindo;
    expect(linha.scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'center',
    });
    expect(mensagemDestacada.value).toBe(10);
    expect(ctx.scrollToBottom).not.toHaveBeenCalled();
    expect(ctx.conversationPanel.scrollTop).toBe(0);
  });

  it('conversa já carregada aberta pelo link: vai à mensagem pedida', async () => {
    const { abrir } = telaDaConversa({
      conversasDaLoja: [
        {
          id: 9,
          dataFetched: true,
          agent_last_seen_at: 1000,
          messages: [daLoja(50, 0, 900)],
        },
      ],
      maisAntigas: [[daLoja(10, 0, 800)], [daLoja(30, 0, 850)]],
    });
    const linha = comMensagemNaTela(10);
    abrir(9, '10');
    await vi.waitFor(() => expect(linha.scrollIntoView).toHaveBeenCalled(), {
      timeout: 500,
    });
    expect(mensagemDestacada.value).toBe(10);
  });

  // Abriu a 9 pela busca, as mensagens dela ainda vinham, e o atendente já foi para a 12:
  // o aviso da 9 chega com a 12 na tela e não pode procurar a mensagem 10 nela.
  it('aviso de abrir que chega depois da troca de conversa não vale para a nova', async () => {
    let chegou;
    const mensagensDaNove = new Promise(resolve => {
      chegou = resolve;
    });
    const { ctx, abrir, aberta, avisos, daLojaPorId } = telaDaConversa({
      conversasDaLoja: [
        { id: 9, agent_last_seen_at: 1000, messages: [daLoja(50, 0, 900)] },
        {
          id: 12,
          dataFetched: true,
          agent_last_seen_at: 1000,
          messages: [daLoja(70, 0, 900)],
        },
      ],
      buscarNaLoja: () => mensagensDaNove,
    });
    abrir(9, '10');
    await assentar();
    abrir(12);
    await aberta(12);
    chegou();
    await vi.waitFor(() => expect(daLojaPorId(9).dataFetched).toBe(true));
    await assentar();
    expect(ctx.$store.dispatch).not.toHaveBeenCalled();
    expect(avisos).not.toHaveBeenCalledWith(avisoDeNaoAchou);
    expect(ctx.citadaPendente).toBeNull();
  });

  // Troca rápida: o pedido da 10 ficou guardado enquanto a 9 abria; o atendente foi
  // para a 12 e voltou à 9 pela lista. A 9 abre normal, não na 10.
  it('pedido não usado não vale quando o atendente volta à conversa pela lista', async () => {
    let liberar;
    const portao = new Promise(resolve => {
      liberar = resolve;
    });
    const { ctx, abrir, aberta, daLojaPorId } = telaDaConversa({
      conversasDaLoja: [
        {
          id: 9,
          dataFetched: true,
          agent_last_seen_at: 1000,
          messages: [daLoja(50, 0, 1100)],
        },
        {
          id: 12,
          dataFetched: true,
          agent_last_seen_at: 1000,
          messages: [daLoja(70, 0, 900)],
        },
      ],
    });
    // A 9 tem não lidas além da página: abrir busca a anterior, que demora.
    ctx.$store.dispatch = vi.fn(async (_acao, { conversationId }) => {
      await portao;
      const conversa = daLojaPorId(conversationId);
      conversa.messages = [daLoja(10, 0, 800), ...conversa.messages];
    });
    const linha = comMensagemNaTela(10);
    abrir(9, '10');
    await vi.waitFor(() =>
      expect(ctx.citadaPendente).toEqual({ conversaId: 9, id: '10' })
    );
    abrir(12);
    await aberta(12);
    liberar();
    await assentar();
    abrir(9);
    await aberta(9);
    await assentar();
    expect(linha.scrollIntoView).not.toHaveBeenCalled();
  });

  // As mensagens da 9 não vieram (rede); o atendente foi para a 12 e, mais tarde, voltou
  // à 9 pela lista, que agora carrega. A 9 abre normal, não na 10.
  it('pedido de quando o carregamento falhou não vale na próxima visita', async () => {
    const buscarNaLoja = vi
      .fn()
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValue();
    const { ctx, abrir, aberta } = telaDaConversa({
      conversasDaLoja: [
        {
          id: 9,
          agent_last_seen_at: 1000,
          messages: [daLoja(10, 0, 800), daLoja(50, 0, 900)],
        },
        {
          id: 12,
          dataFetched: true,
          agent_last_seen_at: 1000,
          messages: [daLoja(70, 0, 900)],
        },
      ],
      buscarNaLoja,
    });
    const linha = comMensagemNaTela(10);
    abrir(9, '10');
    await vi.waitFor(() => expect(buscarNaLoja).toHaveBeenCalledTimes(1));
    await assentar();
    abrir(12);
    await aberta(12);
    abrir(9);
    await aberta(9);
    await assentar();
    expect(linha.scrollIntoView).not.toHaveBeenCalled();
    expect(ctx.scrollToBottom).toHaveBeenCalled();
  });

  it('trocou de conversa enquanto buscava a mensagem: para sem aviso', async () => {
    const avisos = vi.fn();
    emitter.on('newToastMessage', avisos);
    aoFim.push(() => emitter.off('newToastMessage', avisos));
    const ctx = contexto({ mensagens: [daLoja(50, 0, 900)] });
    await ctx.rolarNaPele();
    let liberar;
    const portao = new Promise(resolve => {
      liberar = resolve;
    });
    ctx.$store.dispatch = vi.fn(() => portao);
    const linha = comMensagemNaTela(10);
    const indo = ctx.rolarNaPele(10);
    await assentar();
    ctx.currentChat = { ...ctx.currentChat, id: 12 };
    liberar();
    await indo;
    expect(ctx.$store.dispatch).toHaveBeenCalledTimes(1);
    expect(linha.scrollIntoView).not.toHaveBeenCalled();
    expect(avisos).not.toHaveBeenCalled();
  });

  // Fechou a conversa (a tela saiu) enquanto a página com a mensagem vinha: a página
  // chega, mas não há mais tela para rolar nem a quem avisar.
  it('a tela fechou enquanto buscava a mensagem: para sem aviso nem rolagem', async () => {
    const avisos = vi.fn();
    emitter.on('newToastMessage', avisos);
    aoFim.push(() => emitter.off('newToastMessage', avisos));
    const ctx = contexto({ mensagens: [daLoja(50, 0, 900)] });
    await ctx.rolarNaPele();
    let liberar;
    const portao = new Promise(resolve => {
      liberar = resolve;
    });
    ctx.$store.dispatch = vi.fn(async () => {
      await portao;
      ctx.currentChat.messages = [
        daLoja(10, 0, 800),
        ...ctx.currentChat.messages,
      ];
    });
    const linha = comMensagemNaTela(10);
    const indo = ctx.rolarNaPele(10);
    await assentar();
    ctx.desmontada = true;
    liberar();
    await indo;
    expect(ctx.$store.dispatch).toHaveBeenCalledTimes(1);
    expect(linha.scrollIntoView).not.toHaveBeenCalled();
    expect(avisos).not.toHaveBeenCalled();
  });
});
