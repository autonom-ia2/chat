import AcompanharConversaAPI from 'dashboard/api/acompanharConversa';
import { lerQuemAcompanha, mudarAcompanhar } from '../topo/acompanhar';

// #2138 — entrar ou sair de quem acompanha manda SÓ o id da própria pessoa (POST
// ou DELETE de participants). A lista das outras pessoas nunca vai na chamada.
vi.mock('dashboard/api/acompanharConversa', () => ({
  default: { incluir: vi.fn(), tirar: vi.fn(), quemAcompanha: vi.fn() },
}));

const EU = 7;
const pessoas = (...ids) => ids.map(id => ({ id, name: `Pessoa ${id}` }));
const depois = (...ids) =>
  AcompanharConversaAPI.quemAcompanha.mockResolvedValue({
    data: pessoas(...ids),
  });

beforeEach(() => {
  vi.clearAllMocks();
  AcompanharConversaAPI.incluir.mockResolvedValue({ data: [] });
  AcompanharConversaAPI.tirar.mockResolvedValue({});
});

describe('mudarAcompanhar', () => {
  it('acompanhar faz o POST só com a própria pessoa, sem a lista dos outros', async () => {
    depois(3, 9, EU);
    const ficou = await mudarAcompanhar({
      conversationId: 42,
      euId: EU,
      acompanhar: true,
    });

    expect(AcompanharConversaAPI.incluir).toHaveBeenCalledTimes(1);
    expect(AcompanharConversaAPI.incluir).toHaveBeenCalledWith(42, EU);
    expect(AcompanharConversaAPI.tirar).not.toHaveBeenCalled();
    expect(ficou).toBe(true);
  });

  it('deixar de acompanhar faz o DELETE só com a própria pessoa', async () => {
    depois(3, 9);
    const ficou = await mudarAcompanhar({
      conversationId: 42,
      euId: EU,
      acompanhar: false,
    });

    expect(AcompanharConversaAPI.tirar).toHaveBeenCalledTimes(1);
    expect(AcompanharConversaAPI.tirar).toHaveBeenCalledWith(42, EU);
    expect(AcompanharConversaAPI.incluir).not.toHaveBeenCalled();
    expect(ficou).toBe(true);
  });

  it('o resultado vem da lista relida: se a pessoa não ficou, devolve false', async () => {
    depois(3);
    expect(
      await mudarAcompanhar({ conversationId: 42, euId: EU, acompanhar: true })
    ).toBe(false);

    depois(3, EU);
    expect(
      await mudarAcompanhar({ conversationId: 42, euId: EU, acompanhar: false })
    ).toBe(false);
  });

  it('gravação recusada (ex.: trava de funil) chega a quem chamou', async () => {
    const recusa = Object.assign(new Error('403'), {
      response: { data: { code: 'participants.self_add_restricted' } },
    });
    AcompanharConversaAPI.incluir.mockRejectedValue(recusa);

    await expect(
      mudarAcompanhar({ conversationId: 42, euId: EU, acompanhar: true })
    ).rejects.toBe(recusa);
    expect(AcompanharConversaAPI.quemAcompanha).not.toHaveBeenCalled();
  });

  it('gravou, mas a releitura falhou: vale a resposta da gravação', async () => {
    AcompanharConversaAPI.quemAcompanha.mockRejectedValue(new Error('rede'));
    expect(
      await mudarAcompanhar({ conversationId: 42, euId: EU, acompanhar: true })
    ).toBe(true);
  });
});

describe('lerQuemAcompanha', () => {
  it('devolve os ids', async () => {
    depois(3, EU);
    expect(await lerQuemAcompanha(42)).toEqual([3, EU]);
  });

  it('resposta ilegível lança', async () => {
    AcompanharConversaAPI.quemAcompanha.mockResolvedValue({ data: null });
    await expect(lerQuemAcompanha(42)).rejects.toThrow();
  });
});
