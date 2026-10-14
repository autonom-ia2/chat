import { dataDoVencimento, diaDoVencimento } from '../closeDate';

describe('diaDoVencimento', () => {
  it('guarda o dia em que o card caiu, mesmo à noite', () => {
    expect(diaDoVencimento(new Date(2026, 9, 20, 22, 30))).toBe('2026-10-20');
  });

  it('completa mês e dia com zero', () => {
    expect(diaDoVencimento(new Date(2026, 0, 5, 0, 0))).toBe('2026-01-05');
  });
});

describe('dataDoVencimento', () => {
  // O servidor manda o vencimento como 00:00 UTC; em São Paulo isso é a noite do dia anterior. A grade usa o dia gravado.
  it('usa o dia gravado, não o instante no fuso do navegador', () => {
    const dia = dataDoVencimento('2026-10-20T00:00:00Z');

    expect([
      dia.getFullYear(),
      dia.getMonth(),
      dia.getDate(),
      dia.getHours(),
    ]).toEqual([2026, 9, 20, 0]);
  });

  it('aceita só a data e devolve null sem data', () => {
    expect(dataDoVencimento('2026-10-20').getDate()).toBe(20);
    expect(dataDoVencimento(null)).toBeNull();
    expect(dataDoVencimento('')).toBeNull();
  });
});
