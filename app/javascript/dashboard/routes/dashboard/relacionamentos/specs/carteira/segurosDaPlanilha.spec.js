import {
  SITUACAO_DA_COLUNA,
  chaveDoDestino,
  chaveDoProblemaDoSeguro,
  colunasDosSeguros,
  colunasParaConfirmar,
  colunasQueServem,
  comAEscolhaDaColuna,
  contadoresDosSeguros,
  destinosDeSeguro,
  destinosQueFaltam,
  ehApoliceRepetida,
  ehProblemaDoSeguro,
  numerosDosSeguros,
  obrigatoriosSemColuna,
  segurosConferidos,
  segurosPorTipo,
  temSeguros,
} from '../../carteira/segurosDaPlanilha';

// A planilha que traz seguros, em funções puras (#2897): o que a leitura de
// "Trazer minha lista" diz dos seguros e o que a tela conta a partir dela.
const DESTINOS = [
  'seguro_numero',
  'seguro_seguradora',
  'seguro_tipo',
  'seguro_termina',
  'seguro_comeca',
  'seguro_valor',
  'seguro_bem',
];

const conferida = (extra = {}) => ({
  seguros: { destinos: DESTINOS, faltam: [] },
  resumo: {
    entram: 12,
    seguros: 12,
    pessoas: 9,
    pessoasQueJaEstavam: 2,
    porTipo: { auto: 7, residencial: 0, vida: 3, empresarial: 0, outro: 2 },
    repetidos: 1,
  },
  problemas: [],
  problemasTotal: 0,
  ...extra,
});

describe('o bloco de seguros da leitura', () => {
  it('só a leitura com o bloco tem seguros', () => {
    expect(temSeguros(conferida())).toBe(true);
    expect(temSeguros({ resumo: {} })).toBe(false);
    expect(temSeguros(null)).toBe(false);
  });

  it('diz os destinos obrigatórios que ainda não têm coluna', () => {
    const leitura = conferida({
      seguros: { destinos: DESTINOS, faltam: ['seguro_termina'] },
    });
    expect(destinosQueFaltam(leitura)).toEqual(['seguro_termina']);
    expect(destinosQueFaltam(conferida())).toEqual([]);
    expect(destinosQueFaltam({})).toEqual([]);
  });

  it('as linhas só estão conferidas como seguro sem coluna faltando', () => {
    expect(segurosConferidos(conferida())).toBe(true);
    expect(
      segurosConferidos(
        conferida({ seguros: { destinos: DESTINOS, faltam: ['seguro_tipo'] } })
      )
    ).toBe(false);
    expect(segurosConferidos({ resumo: {} })).toBe(false);
  });
});

describe('os destinos de seguro das colunas', () => {
  it('cada destino que o servidor manda tem nome no catálogo', () => {
    const destinos = destinosDeSeguro(conferida());
    expect(destinos.map(({ value }) => value)).toEqual(DESTINOS);
    destinos.forEach(({ value, chave }) => {
      expect(chave).toBe(chaveDoDestino(value));
      expect(
        chave.startsWith('RELACIONAMENTOS_CARTEIRA.TRAZER.DESTINOS.')
      ).toBe(true);
    });
  });

  it('o destino que a tela não conhece não é oferecido', () => {
    const leitura = conferida({
      seguros: { destinos: ['seguro_numero', 'seguro_novidade'], faltam: [] },
    });
    expect(destinosDeSeguro(leitura).map(({ value }) => value)).toEqual([
      'seguro_numero',
    ]);
    expect(destinosDeSeguro({})).toEqual([]);
  });
});

// A planilha que respondeu "sim": as colunas das pessoas, as de seguro (ainda só
// informação) e o que o servidor sugere para cada coisa do seguro.
const OBRIGATORIOS = DESTINOS.slice(0, 4);
const coluna = (indice, nome, destino = 'informacao') => ({
  indice,
  nome,
  destino,
});
const comColunas = ({ colunas, sugestao = {}, faltam = OBRIGATORIOS }) => ({
  colunas,
  seguros: { destinos: DESTINOS, obrigatorios: OBRIGATORIOS, faltam, sugestao },
  resumo: {},
});
const DA_PLANILHA = [
  coluna(0, 'Nome', 'nome'),
  coluna(1, 'Cel', 'telefone'),
  coluna(2, 'Cidade'),
  coluna(3, 'Apólice'),
  coluna(4, 'Cia'),
  coluna(5, 'Ramo'),
  coluna(6, 'Fim'),
  coluna(7, 'Prêmio'),
];
const SUGESTAO = {
  seguro_numero: 3,
  seguro_seguradora: 4,
  seguro_tipo: 5,
  seguro_termina: 6,
  seguro_valor: 7,
};
const { CONFIRMADA, ESCOLHIDA, SUGERIDA, FALTA, OPCIONAL } = SITUACAO_DA_COLUNA;
const doDestino = (linhas, destino) =>
  linhas.find(linha => linha.destino === destino);
const situacoes = linhas =>
  Object.fromEntries(linhas.map(linha => [linha.destino, linha.situacao]));

describe('onde está cada coisa do seguro', () => {
  it('uma linha por destino, na ordem do servidor, com a coluna sugerida', () => {
    const linhas = colunasDosSeguros(
      comColunas({ colunas: DA_PLANILHA, sugestao: SUGESTAO })
    );

    expect(linhas.map(linha => linha.destino)).toEqual(DESTINOS);
    expect(doDestino(linhas, 'seguro_numero')).toEqual({
      destino: 'seguro_numero',
      chave: chaveDoDestino('seguro_numero'),
      obrigatorio: true,
      situacao: SUGERIDA,
      coluna: 3,
    });
    expect(doDestino(linhas, 'seguro_valor')).toMatchObject({
      obrigatorio: false,
      situacao: SUGERIDA,
      coluna: 7,
    });
  });

  it('sem sugestão, o obrigatório falta e o outro pode ficar sem coluna', () => {
    const linhas = colunasDosSeguros(comColunas({ colunas: DA_PLANILHA }));

    expect(situacoes(linhas)).toEqual({
      seguro_numero: FALTA,
      seguro_seguradora: FALTA,
      seguro_tipo: FALTA,
      seguro_termina: FALTA,
      seguro_comeca: OPCIONAL,
      seguro_valor: OPCIONAL,
      seguro_bem: OPCIONAL,
    });
    linhas.forEach(linha => expect(linha.coluna).toBeNull());
    expect(obrigatoriosSemColuna(linhas)).toEqual(OBRIGATORIOS);
  });

  it('a coluna que o servidor já guarda está confirmada, mesmo com outra sugerida', () => {
    const colunas = DA_PLANILHA.map(item =>
      item.indice === 3 ? { ...item, destino: 'seguro_numero' } : item
    );
    const linhas = colunasDosSeguros(
      comColunas({ colunas, sugestao: { seguro_numero: 2 } })
    );

    expect(doDestino(linhas, 'seguro_numero')).toMatchObject({
      situacao: CONFIRMADA,
      coluna: 3,
    });
  });

  it('a sugestão de uma coluna que a planilha não tem não vale', () => {
    const linhas = colunasDosSeguros(
      comColunas({ colunas: DA_PLANILHA, sugestao: { seguro_numero: 99 } })
    );

    expect(doDestino(linhas, 'seguro_numero')).toMatchObject({
      situacao: FALTA,
      coluna: null,
    });
  });

  it('o que a pessoa escolhe na tela vale mais que a sugestão', () => {
    const leitura = comColunas({ colunas: DA_PLANILHA, sugestao: SUGESTAO });
    const mexidas = comAEscolhaDaColuna(leitura, {}, 'seguro_numero', 2);

    expect(
      doDestino(colunasDosSeguros(leitura, mexidas), 'seguro_numero')
    ).toMatchObject({ situacao: ESCOLHIDA, coluna: 2 });
  });

  it('cada coluna guarda uma coisa só: quem tinha a coluna escolhida fica sem', () => {
    const leitura = comColunas({ colunas: DA_PLANILHA, sugestao: SUGESTAO });
    // O valor está, na verdade, na coluna que foi sugerida para o fim.
    const mexidas = comAEscolhaDaColuna(leitura, {}, 'seguro_valor', 6);
    const linhas = colunasDosSeguros(leitura, mexidas);

    expect(doDestino(linhas, 'seguro_valor')).toMatchObject({
      situacao: ESCOLHIDA,
      coluna: 6,
    });
    expect(doDestino(linhas, 'seguro_termina')).toMatchObject({
      situacao: FALTA,
      coluna: null,
    });
    expect(obrigatoriosSemColuna(linhas)).toEqual(['seguro_termina']);
  });

  it('escolher de volta a coluna que o servidor já guarda não é mudança', () => {
    const colunas = DA_PLANILHA.map(item =>
      item.indice === 3 ? { ...item, destino: 'seguro_numero' } : item
    );
    const leitura = comColunas({ colunas });
    const mexidas = comAEscolhaDaColuna(leitura, {}, 'seguro_numero', 3);

    expect(
      doDestino(colunasDosSeguros(leitura, mexidas), 'seguro_numero')
    ).toMatchObject({ situacao: CONFIRMADA, coluna: 3 });
  });

  it('só servem a um seguro as colunas livres e as que já são de seguro', () => {
    const colunas = DA_PLANILHA.map(item =>
      item.indice === 3 ? { ...item, destino: 'seguro_numero' } : item
    );

    expect(
      colunasQueServem(comColunas({ colunas })).map(({ indice }) => indice)
    ).toEqual([2, 3, 4, 5, 6, 7]);
    expect(colunasQueServem({})).toEqual([]);
  });
});

describe('o que o "Está certo" manda ao servidor', () => {
  it('as colunas da tela que o servidor ainda não guarda, os obrigatórios por último', () => {
    const linhas = colunasDosSeguros(
      comColunas({ colunas: DA_PLANILHA, sugestao: SUGESTAO })
    );

    expect(colunasParaConfirmar(linhas)).toEqual([
      { destino: 'seguro_valor', coluna: 7 },
      { destino: 'seguro_numero', coluna: 3 },
      { destino: 'seguro_seguradora', coluna: 4 },
      { destino: 'seguro_tipo', coluna: 5 },
      { destino: 'seguro_termina', coluna: 6 },
    ]);
  });

  it('a coluna já guardada e o destino sem coluna não são mandados', () => {
    const colunas = DA_PLANILHA.map(item =>
      item.indice === 3 ? { ...item, destino: 'seguro_numero' } : item
    );
    const linhas = colunasDosSeguros(
      comColunas({ colunas, sugestao: { seguro_tipo: 5 } })
    );

    expect(colunasParaConfirmar(linhas)).toEqual([
      { destino: 'seguro_tipo', coluna: 5 },
    ]);
  });

  it('a coluna que a pessoa escolheu vai no lugar da sugerida', () => {
    const leitura = comColunas({ colunas: DA_PLANILHA, sugestao: SUGESTAO });
    const mexidas = comAEscolhaDaColuna(leitura, {}, 'seguro_numero', 2);

    expect(
      colunasParaConfirmar(colunasDosSeguros(leitura, mexidas))
    ).toContainEqual({ destino: 'seguro_numero', coluna: 2 });
  });
});

describe('os números da conferência', () => {
  it('diz os seguros, as pessoas e quantas delas são novas', () => {
    expect(numerosDosSeguros(conferida())).toEqual({
      seguros: 12,
      pessoas: 9,
      pessoasNovas: 7,
      pessoasQueJaEstavam: 2,
      repetidos: 1,
      cancelados: 0,
      semTelefone: 0,
    });
  });

  it('diz os seguros que aqui estão cancelados e as pessoas que entram sem telefone', () => {
    const leitura = conferida({
      resumo: { seguros: 5, pessoas: 4, cancelados: 2, semTelefone: 1 },
    });
    expect(numerosDosSeguros(leitura)).toMatchObject({
      cancelados: 2,
      semTelefone: 1,
    });
  });

  it('sem os números (as linhas ainda não foram conferidas) tudo é zero', () => {
    expect(numerosDosSeguros({ resumo: { entram: 30 } })).toEqual({
      seguros: 0,
      pessoas: 0,
      pessoasNovas: 0,
      pessoasQueJaEstavam: 0,
      repetidos: 0,
      cancelados: 0,
      semTelefone: 0,
    });
  });

  it('as pessoas que já estavam nunca passam das pessoas', () => {
    const leitura = conferida({
      resumo: { seguros: 3, pessoas: 2, pessoasQueJaEstavam: 5 },
    });
    expect(numerosDosSeguros(leitura)).toMatchObject({
      pessoasNovas: 0,
      pessoasQueJaEstavam: 2,
    });
  });

  it('os contadores não trazem os zerados e contam as linhas por carregar', () => {
    const leitura = conferida({
      problemas: [
        { linha: 3, tipo: 'numero', estado: 'aberto' },
        { linha: 4, tipo: 'telefone', estado: 'deixado' },
        { linha: 5, tipo: 'valor', estado: 'guardado' },
      ],
      problemasTotal: 5,
    });
    expect(contadoresDosSeguros(leitura)).toEqual([
      { chave: 'PRECISAM', count: 3 },
      { chave: 'DEIXADOS', count: 1 },
      { chave: 'PESSOAS_NOVAS', count: 7 },
      { chave: 'JA_ESTAVAM', count: 2 },
    ]);
    expect(contadoresDosSeguros({ resumo: {}, problemas: [] })).toEqual([]);
  });

  it('os seguros por tipo vêm na ordem da tela, sem os zerados', () => {
    expect(segurosPorTipo(conferida())).toEqual([
      { tipo: 'auto', count: 7 },
      { tipo: 'vida', count: 3 },
      { tipo: 'outro', count: 2 },
    ]);
    expect(segurosPorTipo({ resumo: {} })).toEqual([]);
  });
});

describe('as linhas com problema no seguro', () => {
  it.each(['numero', 'seguradora', 'falta_termina', 'comeca', 'valor'])(
    'o problema %s é do seguro e tem frase',
    tipo => {
      const problema = { linha: 9, tipo, motivo: 'falta' };
      expect(ehProblemaDoSeguro(problema)).toBe(true);
      expect(ehApoliceRepetida(problema)).toBe(false);
      expect(typeof chaveDoProblemaDoSeguro(problema)).toBe('string');
    }
  );

  it('a apólice repetida é do seguro e pede escolha', () => {
    const problema = { linha: 9, tipo: 'duplicado' };
    expect(ehProblemaDoSeguro(problema)).toBe(true);
    expect(ehApoliceRepetida(problema)).toBe(true);
  });

  it.each(['telefone', 'email', 'nome', 'duplicada', 'sem_contato'])(
    'o problema %s é da pessoa, não do seguro',
    tipo => {
      expect(ehProblemaDoSeguro({ linha: 9, tipo })).toBe(false);
    }
  );

  const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER.PRECISAM.PROBLEMA';
  const frase = (tipo, motivo) => chaveDoProblemaDoSeguro({ tipo, motivo });

  it('o motivo que a tela conhece tem a frase dele', () => {
    expect(frase('numero', 'falta')).toBe(`${BASE}.NUMERO`);
    expect(frase('numero', 'notacao_cientifica')).toBe(
      `${BASE}.NUMERO_ESTRAGADO`
    );
    expect(frase('falta_termina', 'falta')).toBe(`${BASE}.TERMINA`);
    expect(frase('falta_termina', 'data_invalida')).toBe(
      `${BASE}.TERMINA_ILEGIVEL`
    );
    expect(frase('falta_termina', 'termina_antes')).toBe(
      `${BASE}.TERMINA_ANTES`
    );
  });

  // O servidor só manda o motivo na linha aberta.
  it('sem motivo (a linha deixada de fora) ou com motivo novo, a frase não afirma a causa', () => {
    expect(frase('numero')).toBe(`${BASE}.NUMERO_COM_PROBLEMA`);
    expect(frase('numero', 'motivo_novo')).toBe(`${BASE}.NUMERO_COM_PROBLEMA`);
    expect(frase('falta_termina')).toBe(`${BASE}.TERMINA_COM_PROBLEMA`);
    expect(frase('falta_termina', 'motivo_novo')).toBe(
      `${BASE}.TERMINA_COM_PROBLEMA`
    );
    expect(frase('seguradora')).toBe(`${BASE}.SEGURADORA`);
  });
});
