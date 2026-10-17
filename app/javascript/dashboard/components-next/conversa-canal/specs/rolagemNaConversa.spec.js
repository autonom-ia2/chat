import MessagesView from 'dashboard/components/widgets/conversation/MessagesView.vue';
import { emitter } from 'shared/helpers/mitt';
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
