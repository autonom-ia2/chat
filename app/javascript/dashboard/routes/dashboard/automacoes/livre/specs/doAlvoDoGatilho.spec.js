import { doAlvoDoGatilho } from '../catalogo';

// #2499: o editor só oferece o valor que o alvo do gatilho alcança.
describe('doAlvoDoGatilho', () => {
  const catalogo = {
    gatilhos: [
      { tipo: 'conversa.criada', alvo: 'Conversation' },
      { tipo: 'card.entrou_na_etapa', alvo: 'Crm::Card' },
    ],
    alvos: {
      Conversation: ['conversa', 'contato'],
      'Crm::Card': ['card', 'conversa', 'contato'],
    },
    valores: [
      { caminho: 'conversa.status', base: 'conversa' },
      { caminho: 'card.valor', base: 'card' },
      { caminho: 'contato.nome', base: 'contato' },
      { caminho: 'mensagem.tipo', so_no_gatilho: 'mensagem.criada' },
    ],
  };
  const caminhos = dados => dados.valores.map(item => item.caminho);

  it('tira o card do gatilho de conversa e mantém a mensagem, que tem regra própria', () => {
    expect(caminhos(doAlvoDoGatilho(catalogo, 'conversa.criada'))).toEqual([
      'conversa.status',
      'contato.nome',
      'mensagem.tipo',
    ]);
  });

  it('no gatilho de card, oferece o card e as pontes', () => {
    expect(caminhos(doAlvoDoGatilho(catalogo, 'card.entrou_na_etapa'))).toEqual(
      ['conversa.status', 'card.valor', 'contato.nome', 'mensagem.tipo']
    );
  });

  // G25: a ação que lê o card no caminho só entra no gatilho de card.
  it('tira do gatilho de conversa a ação que lê o card no caminho', () => {
    const comPassos = {
      ...catalogo,
      passos: [
        {
          tipo: 'acao',
          nome: 'card_fechar',
          caminho: { id: { $valor: 'card.id' } },
        },
        {
          tipo: 'acao',
          nome: 'conversa_status',
          caminho: { id: { $valor: 'conversa.id' } },
        },
        {
          tipo: 'acao',
          nome: 'etiqueta_alterar',
          caminho: { id: { escolher: 'etiqueta' } },
        },
        { tipo: 'esperar' },
      ],
    };
    const nomes = dados => dados.passos.map(item => item.nome || item.tipo);

    expect(nomes(doAlvoDoGatilho(comPassos, 'conversa.criada'))).toEqual([
      'conversa_status',
      'etiqueta_alterar',
      'esperar',
    ]);
    expect(nomes(doAlvoDoGatilho(comPassos, 'card.entrou_na_etapa'))).toEqual([
      'card_fechar',
      'conversa_status',
      'etiqueta_alterar',
      'esperar',
    ]);
  });

  // #2716: o gatilho de conversa lê o card da conversa, só com a chave de funis.
  it('no gatilho de conversa, oferece o card só a quem tem a chave de funis', () => {
    const comCard = {
      ...catalogo,
      alvos: {
        ...catalogo.alvos,
        Conversation: ['conversa', 'contato', 'card'],
      },
    };
    expect(
      caminhos(doAlvoDoGatilho(comCard, 'conversa.criada', false, true))
    ).toEqual([
      'conversa.status',
      'card.valor',
      'contato.nome',
      'mensagem.tipo',
    ]);
    expect(caminhos(doAlvoDoGatilho(comCard, 'conversa.criada'))).toEqual([
      'conversa.status',
      'contato.nome',
      'mensagem.tipo',
    ]);
    expect(
      caminhos(doAlvoDoGatilho(comCard, 'card.entrou_na_etapa', false, false))
    ).toContain('card.valor');
  });

  // Decisão 19: o card da conversa (#2716) é só para ler. Mesmo com a base
  // 'card' nos alvos da conversa e a chave de funis, a ação que lê o card no
  // caminho fica fora do gatilho de conversa.
  it('com o card da conversa, a ação no card continua fora do gatilho de conversa', () => {
    const comCardEPassos = {
      ...catalogo,
      alvos: {
        ...catalogo.alvos,
        Conversation: ['conversa', 'contato', 'card'],
      },
      passos: [
        {
          tipo: 'acao',
          nome: 'card_fechar',
          caminho: { id: { $valor: 'card.id' } },
        },
        {
          tipo: 'acao',
          nome: 'conversa_status',
          caminho: { id: { $valor: 'conversa.id' } },
        },
      ],
    };
    const nomes = dados => dados.passos.map(item => item.nome);

    expect(
      nomes(doAlvoDoGatilho(comCardEPassos, 'conversa.criada', false, true))
    ).toEqual(['conversa_status']);
    expect(
      nomes(doAlvoDoGatilho(comCardEPassos, 'conversa.criada', true, true))
    ).toEqual(['conversa_status']);
    expect(
      nomes(doAlvoDoGatilho(comCardEPassos, 'card.entrou_na_etapa'))
    ).toEqual(['card_fechar', 'conversa_status']);
  });

  it('sem gatilho escolhido, devolve o catálogo como veio', () => {
    expect(doAlvoDoGatilho(catalogo, undefined)).toBe(catalogo);
    expect(doAlvoDoGatilho(null, 'conversa.criada')).toBeNull();
  });
});
