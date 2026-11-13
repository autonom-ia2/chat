import {
  chaveDoDestino,
  chaveDoProblemaDoSeguro,
  contadoresDosSeguros,
  destinosDeSeguro,
  destinosQueFaltam,
  ehApoliceRepetida,
  ehProblemaDoSeguro,
  numerosDosSeguros,
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

describe('os números da conferência', () => {
  it('diz os seguros, as pessoas e quantas delas são novas', () => {
    expect(numerosDosSeguros(conferida())).toEqual({
      seguros: 12,
      pessoas: 9,
      pessoasNovas: 7,
      pessoasQueJaEstavam: 2,
      repetidos: 1,
    });
  });

  it('sem os números (as linhas ainda não foram conferidas) tudo é zero', () => {
    expect(numerosDosSeguros({ resumo: { entram: 30 } })).toEqual({
      seguros: 0,
      pessoas: 0,
      pessoasNovas: 0,
      pessoasQueJaEstavam: 0,
      repetidos: 0,
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
