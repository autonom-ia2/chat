import ConversationInboxApi from 'dashboard/api/inbox/conversation';
import { listaAoAcompanhar, mudarAcompanhar } from '../topo/acompanhar';

// #2138 — a API grava a LISTA INTEIRA de quem acompanha: a lista é lida na hora
// e só a própria pessoa entra ou sai.
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { fetchParticipants: vi.fn() },
}));

const EU = 7;
const pessoas = (...ids) => ids.map(id => ({ id, name: `Pessoa ${id}` }));

describe('listaAoAcompanhar', () => {
  it('incluir põe só a pessoa e mantém os outros', () => {
    expect(
      listaAoAcompanhar({ atuais: [3, 5], euId: EU, acompanhar: true })
    ).toEqual([3, 5, EU]);
  });

  it('tirar tira só a pessoa e mantém os outros', () => {
    expect(
      listaAoAcompanhar({ atuais: [3, EU, 5], euId: EU, acompanhar: false })
    ).toEqual([3, 5]);
  });

  it('incluir de novo não duplica', () => {
    expect(
      listaAoAcompanhar({ atuais: [EU, 3], euId: EU, acompanhar: true })
    ).toEqual([3, EU]);
  });
});

describe('mudarAcompanhar', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lê a lista do servidor antes de gravar: quem uma colega incluiu há pouco continua', async () => {
    // A tela ainda acha que só a 3 acompanha; no servidor já há a 3 e a 9.
    ConversationInboxApi.fetchParticipants.mockResolvedValue({
      data: pessoas(3, 9),
    });
    const gravar = vi.fn();

    const gravada = await mudarAcompanhar({
      conversationId: 42,
      euId: EU,
      acompanhar: true,
      gravar,
    });

    expect(ConversationInboxApi.fetchParticipants).toHaveBeenCalledWith(42);
    expect(gravar).toHaveBeenCalledWith({
      conversationId: 42,
      userIds: [3, 9, EU],
    });
    expect(gravada).toEqual([3, 9, EU]);
  });

  it('ao deixar de acompanhar, os outros continuam', async () => {
    ConversationInboxApi.fetchParticipants.mockResolvedValue({
      data: pessoas(3, EU, 9),
    });
    const gravar = vi.fn();

    await mudarAcompanhar({
      conversationId: 42,
      euId: EU,
      acompanhar: false,
      gravar,
    });

    expect(gravar).toHaveBeenCalledWith({
      conversationId: 42,
      userIds: [3, 9],
    });
  });

  it('sem conseguir ler a lista, não grava nada (nunca sobrescreve vazia)', async () => {
    ConversationInboxApi.fetchParticipants.mockRejectedValue(new Error('rede'));
    const gravar = vi.fn();

    await expect(
      mudarAcompanhar({
        conversationId: 42,
        euId: EU,
        acompanhar: false,
        gravar,
      })
    ).rejects.toThrow('rede');
    expect(gravar).not.toHaveBeenCalled();
  });

  it('resposta ilegível também não grava', async () => {
    ConversationInboxApi.fetchParticipants.mockResolvedValue({ data: null });
    const gravar = vi.fn();

    await expect(
      mudarAcompanhar({
        conversationId: 42,
        euId: EU,
        acompanhar: true,
        gravar,
      })
    ).rejects.toThrow();
    expect(gravar).not.toHaveBeenCalled();
  });

  it('tirar quem não está na lista não grava (não manda lista vazia por engano)', async () => {
    ConversationInboxApi.fetchParticipants.mockResolvedValue({ data: [] });
    const gravar = vi.fn();

    await mudarAcompanhar({
      conversationId: 42,
      euId: EU,
      acompanhar: false,
      gravar,
    });

    expect(gravar).not.toHaveBeenCalled();
  });

  it('a lista só fica vazia quando a pessoa era a única e saiu', async () => {
    ConversationInboxApi.fetchParticipants.mockResolvedValue({
      data: pessoas(EU),
    });
    const gravar = vi.fn();

    await mudarAcompanhar({
      conversationId: 42,
      euId: EU,
      acompanhar: false,
      gravar,
    });

    expect(gravar).toHaveBeenCalledWith({ conversationId: 42, userIds: [] });
  });
});
