import { diasEmFaixa, quandoSai, tempoAte } from './funil';

describe('tempoAte', () => {
  it('says each wait in everyday words', () => {
    expect(tempoAte(4)).toEqual({ chave: 'EM_HORAS', n: 4 });
    expect(tempoAte(20)).toEqual({ chave: 'AMANHA', n: 1 });
    expect(tempoAte(72)).toEqual({ chave: 'EM_DIAS', n: 3 });
    expect(tempoAte(336)).toEqual({ chave: 'EM_SEMANAS', n: 2 });
  });
});

describe('diasEmFaixa', () => {
  it('joins days in a row and keeps the rest as a list', () => {
    expect(diasEmFaixa([0, 1, 2, 3, 4, 5, 6])).toEqual({ tipo: 'TODOS' });
    expect(diasEmFaixa([5, 1, 2, 3, 4])).toEqual({
      tipo: 'FAIXA',
      de: 1,
      ate: 5,
    });
    expect(diasEmFaixa([1, 3, 5])).toEqual({ tipo: 'LISTA', dias: [1, 3, 5] });
  });
});

describe('quandoSai', () => {
  const semana = { dias: [1, 2, 3, 4, 5], inicio: 8, fim: 20 };

  it('waits for the next allowed hour and day', () => {
    // Última mensagem: segunda, 10h.
    expect(quandoSai({ ...semana, intervalos: [20, 72, 168] })).toEqual([
      // 20h depois = terça 6h → terça 8h.
      { dia: 2, hora: 8, semanaQueVem: false },
      // 72h depois = quinta 10h.
      { dia: 4, hora: 10, semanaQueVem: false },
      // 168h depois = segunda seguinte 10h.
      { dia: 1, hora: 10, semanaQueVem: true },
    ]);
  });

  it('skips days that are not allowed', () => {
    // 108h depois = sexta 22h → depois das 20h → sábado → segunda 8h.
    expect(quandoSai({ ...semana, intervalos: [108] })).toEqual([
      { dia: 1, hora: 8, semanaQueVem: true },
    ]);
  });
});
