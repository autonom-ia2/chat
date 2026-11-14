// O cliente de API de "Trazer minha lista" simulado (#2896): um `vi.fn()` por
// pedido. Fica separado do resto do apoio porque é carregado de dentro do
// `vi.mock` do próprio cliente (não pode importar quem o importa).
export const apiDeMentira = () => ({
  enviar: vi.fn(),
  leitura: vi.fn(),
  responder: vi.fn(),
  consertar: vi.fn(),
  deixarDeFora: vi.fn(),
  reabrir: vi.fn(),
  trocarColuna: vi.fn(),
  trazer: vi.fn(),
  listas: vi.fn(),
  andamento: vi.fn(),
  confirmar: vi.fn(),
});
