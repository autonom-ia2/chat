import { h, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import BotaoDeDescer from '../BotaoDeDescer.vue';
import FaixaDeNaoLidas from '../FaixaDeNaoLidas.vue';
import {
  DESTAQUE_EM_MS,
  destacarMensagem,
  mensagemDestacada,
} from '../destaqueDaCitada';
import {
  buscarAteAchar,
  deveDescer,
  inicioDaContagem,
  marcoDeNaoLidas,
  naoLidasCarregadas,
  novasDoCliente,
  pertoDoFim,
  TETO_DE_PAGINAS,
  topoDaFaixa,
} from '../rolagemDaPele';
import en from '../../../i18n/locale/en/conversaCanal.json';
import ptBR from '../../../i18n/locale/pt_BR/conversaCanal.json';

// Frente "não lidas, rolagem e citação" (#1702): abrir na 1ª não lida com a faixa e o
// número exato, selo de novas no botão de descer, citação que busca a mensagem antiga.

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { en, pt_BR: ptBR },
});

// Mensagens da loja (snake_case): 0 = do cliente, 1 = nossa, 2 = atividade.
const daLoja = (id, tipo, criadaEm, extra = {}) => ({
  id,
  message_type: tipo,
  created_at: criadaEm,
  content_attributes: {},
  ...extra,
});

describe('faixa de não lidas (marcoDeNaoLidas)', () => {
  const lidaEm = 1000;
  const mensagens = [
    daLoja(1, 0, 900),
    daLoja(2, 1, 950),
    daLoja(3, 1, 1001), // robô respondeu depois da leitura: não abre a faixa
    daLoja(4, 0, 1002),
    daLoja(5, 0, 1003, { content_attributes: { c2y_hidden: true } }),
    daLoja(6, 2, 1004),
    ...Array.from({ length: 12 }, (_, i) => daLoja(10 + i, 0, 1005 + i)),
  ];

  it('fica na 1ª do cliente depois da leitura e conta todas, sem "9+"', () => {
    expect(marcoDeNaoLidas(77, mensagens, lidaEm)).toEqual({
      conversaId: 77,
      pronta: true,
      primeiraNaoLida: 4,
      quantidade: 13,
    });
  });

  it('não conta a escondida pela pele nem a nossa', () => {
    const marco = marcoDeNaoLidas(1, mensagens.slice(0, 6), lidaEm);
    expect(marco.quantidade).toBe(1);
  });

  it('sem nada do cliente depois da leitura, não há faixa', () => {
    const marco = marcoDeNaoLidas(1, mensagens.slice(0, 3), lidaEm);
    expect(marco.primeiraNaoLida).toBeNull();
    expect(marco.quantidade).toBe(0);
  });

  it('conversa nunca aberta por atendente: sem faixa, abre no fim', () => {
    expect(marcoDeNaoLidas(1, mensagens.slice(0, 4), null)).toMatchObject({
      primeiraNaoLida: null,
      quantidade: 0,
    });
  });

  it('sabe se as não lidas já vieram todas (a mais antiga já era lida)', () => {
    expect(naoLidasCarregadas(mensagens, lidaEm)).toBe(true);
    expect(naoLidasCarregadas(mensagens.slice(3), lidaEm)).toBe(false);
    // Sem leitura nenhuma não busca páginas antigas: conta o que veio.
    expect(naoLidasCarregadas(mensagens, null)).toBe(true);
    expect(naoLidasCarregadas([], lidaEm)).toBe(false);
  });
});

describe('posição e decisão de descer', () => {
  const painel = (scrollHeight, scrollTop, clientHeight) => ({
    scrollHeight,
    scrollTop,
    clientHeight,
  });

  it('perto do fim até 300 px; lendo lá em cima passa disso', () => {
    expect(pertoDoFim(painel(2000, 1500, 500))).toBe(true);
    expect(pertoDoFim(painel(2000, 1200, 500))).toBe(true);
    expect(pertoDoFim(painel(2000, 1199, 500))).toBe(false);
  });

  it('a faixa abre perto do topo, abaixo da etiqueta do dia', () => {
    expect(topoDaFaixa(800)).toBe(744);
    expect(topoDaFaixa(20)).toBe(0);
  });

  it('cliente escrevendo não puxa quem está lendo lá em cima', () => {
    expect(
      deveDescer({
        estavaNoFim: false,
        ultimaAntes: 10,
        ultima: { id: 11, message_type: 0 },
      })
    ).toBe(false);
  });

  it('quem está no fim acompanha; o envio do atendente sempre desce', () => {
    expect(
      deveDescer({
        estavaNoFim: true,
        ultimaAntes: 10,
        ultima: { id: 11, message_type: 0 },
      })
    ).toBe(true);
    expect(
      deveDescer({
        estavaNoFim: false,
        ultimaAntes: 10,
        ultima: { id: 'pendente-1', message_type: 1 },
      })
    ).toBe(true);
  });

  it('aviso sem mensagem nova (conversa atualizada) não mexe em quem está em cima', () => {
    expect(
      deveDescer({
        estavaNoFim: false,
        ultimaAntes: 11,
        ultima: { id: 11, message_type: 1 },
      })
    ).toBe(false);
  });
});

describe('citação de mensagem que ainda não veio (buscarAteAchar)', () => {
  it('carrega páginas anteriores até achar', async () => {
    const carregadas = [30, 31];
    const carregarMais = vi.fn(async () => {
      carregadas.unshift(carregadas[0] - 1);
    });
    const achou = await buscarAteAchar({
      achou: () => carregadas.includes(27),
      temMais: () => true,
      carregarMais,
    });
    expect(achou).toBe(true);
    expect(carregarMais).toHaveBeenCalledTimes(3);
  });

  it('já carregada: não busca nada', async () => {
    const carregarMais = vi.fn();
    const achou = await buscarAteAchar({
      achou: () => true,
      temMais: () => true,
      carregarMais,
    });
    expect(achou).toBe(true);
    expect(carregarMais).not.toHaveBeenCalled();
  });

  it('para no teto de páginas', async () => {
    const carregarMais = vi.fn(async () => {});
    const achou = await buscarAteAchar({
      achou: () => false,
      temMais: () => true,
      carregarMais,
    });
    expect(achou).toBe(false);
    expect(carregarMais).toHaveBeenCalledTimes(TETO_DE_PAGINAS);
  });

  it('para quando a conversa acabou', async () => {
    let paginas = 2;
    const carregarMais = vi.fn(async () => {
      paginas -= 1;
    });
    const achou = await buscarAteAchar({
      achou: () => false,
      temMais: () => paginas > 0,
      carregarMais,
    });
    expect(achou).toBe(false);
    expect(carregarMais).toHaveBeenCalledTimes(2);
  });
});

describe('destaque da mensagem citada', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('fica destacada por 3 s e apaga', () => {
    destacarMensagem('42');
    expect(mensagemDestacada.value).toBe(42);
    vi.advanceTimersByTime(DESTAQUE_EM_MS - 1);
    expect(mensagemDestacada.value).toBe(42);
    vi.advanceTimersByTime(1);
    expect(mensagemDestacada.value).toBeNull();
  });

  it('outra citação no meio recomeça o tempo', () => {
    destacarMensagem(1);
    vi.advanceTimersByTime(2000);
    destacarMensagem(2);
    vi.advanceTimersByTime(2000);
    expect(mensagemDestacada.value).toBe(2);
    vi.advanceTimersByTime(1000);
    expect(mensagemDestacada.value).toBeNull();
  });
});

describe('FaixaDeNaoLidas', () => {
  it.each([
    [1, '1 mensagem não lida'],
    [13, '13 mensagens não lidas'],
  ])('%i → "%s"', (quantidade, texto) => {
    const wrapper = mount(FaixaDeNaoLidas, {
      props: { quantidade },
      global: { plugins: [i18n] },
    });
    expect(wrapper.find('[data-faixa-nao-lidas]').text()).toBe(texto);
  });
});

describe('contagem do botão de descer', () => {
  const doCliente = (id, conversationId = 5) => ({
    id,
    conversationId,
    messageType: 0,
  });
  const nossa = id => ({ id, conversationId: 5, messageType: 1 });

  it('conta só as do cliente a partir do início', () => {
    const lista = [doCliente(1), nossa(2), doCliente(3), doCliente(4)];
    expect(novasDoCliente(lista, 3)).toBe(2);
    expect(novasDoCliente(lista, null)).toBe(0);
  });

  it('começa na não lida da faixa ou logo depois da última', () => {
    const lista = [doCliente(1), nossa(2), { id: 'pendente', messageType: 1 }];
    expect(inicioDaContagem(lista, 1)).toBe(1);
    expect(inicioDaContagem(lista, null)).toBe(3);
    expect(inicioDaContagem([], null)).toBeNull();
  });
});

describe('BotaoDeDescer', () => {
  let medidas;
  const montar = props =>
    mount(
      {
        props: ['mensagens', 'primeiraNaoLida'],
        render() {
          return h('ul', { class: 'conversation-panel' }, [
            h(BotaoDeDescer, {
              mensagens: this.mensagens,
              primeiraNaoLida: this.primeiraNaoLida,
            }),
          ]);
        },
      },
      {
        props,
        attachTo: document.body,
        global: { plugins: [i18n], stubs: { Icon: true } },
      }
    );
  const rolar = async (wrapper, scrollTop) => {
    const painel = wrapper.find('.conversation-panel').element;
    medidas.scrollTop = scrollTop;
    painel.dispatchEvent(new Event('scroll'));
    await nextTick();
  };
  const selo = wrapper => wrapper.find('[data-novas-do-cliente]');

  beforeEach(() => {
    medidas = { scrollHeight: 3000, scrollTop: 2500, clientHeight: 500 };
    ['scrollHeight', 'scrollTop', 'clientHeight'].forEach(chave => {
      Object.defineProperty(HTMLElement.prototype, chave, {
        configurable: true,
        get() {
          return this.classList.contains('conversation-panel')
            ? medidas[chave]
            : 0;
        },
        set() {},
      });
    });
  });

  afterEach(() => {
    ['scrollHeight', 'scrollTop', 'clientHeight'].forEach(chave => {
      delete HTMLElement.prototype[chave];
    });
  });

  const base = [
    { id: 1, conversationId: 5, messageType: 0 },
    { id: 2, conversationId: 5, messageType: 1 },
  ];

  it('lendo lá em cima, as do cliente que chegam acendem o selo; descer zera', async () => {
    const wrapper = montar({ mensagens: base, primeiraNaoLida: null });
    await rolar(wrapper, 1000);
    expect(selo(wrapper).exists()).toBe(false);

    await wrapper.setProps({
      mensagens: [
        ...base,
        { id: 3, conversationId: 5, messageType: 0 },
        { id: 4, conversationId: 5, messageType: 1 },
        { id: 5, conversationId: 5, messageType: 0 },
      ],
    });
    expect(selo(wrapper).text()).toBe('2');
    expect(wrapper.find('button').attributes('aria-label')).toContain(
      '2 mensagens novas'
    );

    await rolar(wrapper, 2500);
    expect(selo(wrapper).exists()).toBe(false);
    await rolar(wrapper, 1000);
    expect(selo(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('aberta na faixa, conta as não lidas que estão abaixo', async () => {
    const mensagens = [
      ...base,
      { id: 3, conversationId: 5, messageType: 0 },
      { id: 4, conversationId: 5, messageType: 0 },
    ];
    const wrapper = montar({ mensagens, primeiraNaoLida: null });
    await wrapper.setProps({ primeiraNaoLida: 3 });
    await rolar(wrapper, 500);
    expect(selo(wrapper).text()).toBe('2');
    wrapper.unmount();
  });

  it('a faixa que some depois de lida não zera a contagem do botão', async () => {
    const mensagens = [
      ...base,
      { id: 3, conversationId: 5, messageType: 0 },
      { id: 4, conversationId: 5, messageType: 0 },
    ];
    const wrapper = montar({ mensagens, primeiraNaoLida: null });
    await wrapper.setProps({ primeiraNaoLida: 3 });
    await wrapper.setProps({ primeiraNaoLida: null });
    await rolar(wrapper, 500);
    expect(selo(wrapper).text()).toBe('2');
    wrapper.unmount();
  });
});
