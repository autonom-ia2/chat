import { useIrAoGuia } from '../useIrAoGuia';

// #2889 — a pergunta do topo e o modelo levam o pedido ao Guia pelo estado da navegação, com os arquivos de verdade.
const { routerPush } = vi.hoisted(() => ({ routerPush: vi.fn() }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) => `${chave}|${valores.titulo}|${valores.texto}`,
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 7 } }),
  useRouter: () => ({ push: routerPush }),
}));

describe('useIrAoGuia', () => {
  beforeEach(() => routerPush.mockClear());

  it('o pedido escrito vai com os arquivos juntados', () => {
    const print = new File(['x'], 'print.png', { type: 'image/png' });
    useIrAoGuia().pedir({ texto: 'avisar o time', anexos: [print] });
    expect(routerPush).toHaveBeenCalledWith({
      name: 'automacoes_nova',
      params: { accountId: 7 },
      state: { pedidoAutomacao: 'avisar o time', anexosAutomacao: [print] },
    });
    expect(routerPush.mock.calls[0][0].state.anexosAutomacao[0]).toBeInstanceOf(
      File
    );
  });

  it('só arquivo, sem texto, também vai; vazio não leva campo', () => {
    const print = new File(['x'], 'print.png', { type: 'image/png' });
    useIrAoGuia().pedir({ texto: '', anexos: [print] });
    expect(routerPush.mock.calls[0][0].state).toEqual({
      anexosAutomacao: [print],
    });
  });

  it('falar abre o Guia já pronto para a voz', () => {
    useIrAoGuia().falar();
    expect(routerPush.mock.calls[0][0].state).toEqual({ pedidoPorVoz: true });
  });

  it('o modelo vai como pedido com título e texto', () => {
    useIrAoGuia().usarModelo({ titulo: 'A', texto: 'B' });
    expect(routerPush.mock.calls[0][0].state).toEqual({
      pedidoAutomacao: 'AUTOMACAO_MODELOS.PEDIDO|A|B',
    });
  });
});
