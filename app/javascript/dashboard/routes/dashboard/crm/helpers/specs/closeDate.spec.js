import { diaDoVencimento } from '../closeDate';

describe('diaDoVencimento', () => {
  it('guarda o dia em que o card caiu, mesmo à noite', () => {
    expect(diaDoVencimento(new Date(2026, 9, 20, 22, 30))).toBe('2026-10-20');
  });

  it('aceita o começo do dia e completa com zero', () => {
    expect(diaDoVencimento(new Date(2026, 0, 5, 0, 0))).toBe('2026-01-05');
  });
});
