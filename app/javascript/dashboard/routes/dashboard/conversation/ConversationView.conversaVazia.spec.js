import ConversationView from './ConversationView.vue';

// #2211 — a conversa vazia ("Escrever" na busca da lista) só abre com a chave lista_quem_espera e para quem
// pode começar conversa. Desligada a chave, ?comecar= e ?telefone= não mudam nada: a tela é a de sempre.
const { conversaVazia, showConversationList } = ConversationView.computed;

const tela = (extra = {}) => {
  const ctx = {
    listaNova: true,
    podeComecar: true,
    conversationId: 0,
    isOnExpandedLayout: false,
    noCelular: false,
    $route: { query: { comecar: '3' } },
    ...extra,
  };
  ctx.conversaVazia = conversaVazia.call(ctx);
  return ctx;
};

describe('ConversationView: conversa vazia (#2211)', () => {
  it('chave desligada: ignora ?comecar= e ?telefone=, como na main', () => {
    expect(tela({ listaNova: false }).conversaVazia).toBeNull();
    expect(
      tela({
        listaNova: false,
        $route: { query: { telefone: '+5511955554444' } },
      }).conversaVazia
    ).toBeNull();
    expect(
      tela({
        listaNova: false,
        $route: { query: { email: 'nova@exemplo.test' } },
      }).conversaVazia
    ).toBeNull();
    const noCelular = tela({ listaNova: false, noCelular: true });
    expect(showConversationList.call(noCelular)).toBe(true);
  });

  it('chave ligada: abre a conversa vazia do contato ou do telefone novo', () => {
    expect(tela().conversaVazia).toEqual({
      contatoId: '3',
      telefone: '',
      email: '',
      caixasLivres: [],
      caixasPermitidas: [],
    });
    expect(
      tela({ $route: { query: { telefone: '+5511955554444' } } }).conversaVazia
    ).toEqual({
      contatoId: '',
      telefone: '+5511955554444',
      email: '',
      caixasLivres: [],
      caixasPermitidas: [],
    });
    expect(
      tela({ $route: { query: { email: 'nova@exemplo.test', caixas: '4' } } })
        .conversaVazia
    ).toEqual({
      contatoId: '',
      telefone: '',
      email: 'nova@exemplo.test',
      caixasLivres: [],
      caixasPermitidas: ['4'],
    });
  });

  it('quem só lê conversas não começa conversa', () => {
    expect(tela({ podeComecar: false }).conversaVazia).toBeNull();
  });

  it('com uma conversa aberta, a conversa vazia não aparece', () => {
    expect(tela({ conversationId: 12 }).conversaVazia).toBeNull();
  });

  it('no celular, a conversa vazia ocupa a tela (a lista some)', () => {
    expect(showConversationList.call(tela({ noCelular: true }))).toBe(false);
    expect(showConversationList.call(tela())).toBe(true);
  });
});
