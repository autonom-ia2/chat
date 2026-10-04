import {
  useGuiaPedido,
  usePedidoPendente,
} from 'dashboard/composables/useGuiaPedido';

const { atualizarUI } = vi.hoisted(() => ({ atualizarUI: vi.fn() }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings: atualizarUI }),
}));

const PAINEL_ABERTO = {
  is_autonomia_guide_panel_open: true,
  is_autonomia_copilot_panel_open: false,
  is_contact_sidebar_open: false,
};

describe('useGuiaPedido', () => {
  afterEach(() => {
    usePedidoPendente().consumir();
    atualizarUI.mockClear();
  });

  it('abre o painel do Guia e deixa a pergunta esperando', () => {
    useGuiaPedido().pedirAoGuia('  Como conecto o WhatsApp?  ');

    expect(atualizarUI).toHaveBeenCalledWith(PAINEL_ABERTO);
    expect(usePedidoPendente().pedido.value).toBe('Como conecto o WhatsApp?');
  });

  it('o pedido sai uma vez só: consumir devolve o texto e limpa', () => {
    useGuiaPedido().pedirAoGuia('Criar um funil');
    const { pedido, consumir } = usePedidoPendente();

    expect(consumir()).toBe('Criar um funil');
    expect(pedido.value).toBe('');
    expect(consumir()).toBe('');
  });

  it('sem texto, só abre o painel', () => {
    useGuiaPedido().pedirAoGuia('   ');
    useGuiaPedido().pedirAoGuia();

    expect(atualizarUI).toHaveBeenCalledTimes(2);
    expect(atualizarUI).toHaveBeenCalledWith(PAINEL_ABERTO);
    expect(usePedidoPendente().pedido.value).toBe('');
  });

  it('o painel só lê o pedido: não consegue trocá-lo por fora', () => {
    useGuiaPedido().pedirAoGuia('Ver relatórios');
    const { pedido } = usePedidoPendente();

    pedido.value = 'outro';

    expect(pedido.value).toBe('Ver relatórios');
  });
});
