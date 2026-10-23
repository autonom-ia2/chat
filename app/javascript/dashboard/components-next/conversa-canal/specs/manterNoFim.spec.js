import MessagesView from 'dashboard/components/widgets/conversation/MessagesView.vue';

// A caixa de resposta cresce (citação, texto longo) e a lista encolhe: quem estava no
// fim continua vendo a última mensagem (#2113). Métodos sobre um "this" de mentira.
const { methods } = MessagesView;

const painelCom = ({ scrollHeight, clientHeight, scrollTop }) => {
  const painel = document.createElement('ul');
  Object.defineProperty(painel, 'scrollHeight', { value: scrollHeight });
  Object.defineProperty(painel, 'clientHeight', { value: clientHeight });
  painel.scrollTop = scrollTop;
  return painel;
};

const contexto = painel => {
  const ctx = {
    conversationPanel: painel,
    emailNovo: false,
    isProgrammaticScroll: false,
    hasUserScrolled: false,
    noFimDoPainel: true,
    fetchPreviousMessages: vi.fn(),
  };
  Object.entries(methods).forEach(([nome, metodo]) => {
    if (!(nome in ctx)) ctx[nome] = metodo.bind(ctx);
  });
  return ctx;
};

describe('lista no fim quando a caixa de resposta cresce', () => {
  it('quem estava no fim continua no fim', () => {
    const painel = painelCom({
      scrollHeight: 1000,
      clientHeight: 400,
      scrollTop: 600,
    });
    const ctx = contexto(painel);

    ctx.handleScroll({ target: painel });
    ctx.manterNoFim();

    expect(ctx.noFimDoPainel).toBe(true);
    expect(painel.scrollTop).toBe(1000);
  });

  it('quem está lendo mais acima não é puxado para o fim', () => {
    const painel = painelCom({
      scrollHeight: 1000,
      clientHeight: 400,
      scrollTop: 200,
    });
    const ctx = contexto(painel);

    ctx.handleScroll({ target: painel });
    ctx.manterNoFim();

    expect(ctx.noFimDoPainel).toBe(false);
    expect(painel.scrollTop).toBe(200);
  });

  it('no e-mail novo (mais recente no topo) não mexe', () => {
    const painel = painelCom({
      scrollHeight: 1000,
      clientHeight: 400,
      scrollTop: 0,
    });
    const ctx = contexto(painel);
    ctx.emailNovo = true;

    ctx.manterNoFim();

    expect(painel.scrollTop).toBe(0);
  });
});
