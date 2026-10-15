import { duracao } from '../dashboardOutcomes';

// #1498 — tempo de solução em palavras curtas.
describe('duracao', () => {
  it('uses days and hours, hours and minutes, or minutes', () => {
    expect(duracao(100800)).toEqual({ chave: 'DIAS', valores: { d: 1, h: 4 } });
    expect(duracao(12000)).toEqual({
      chave: 'HORAS',
      valores: { h: 3, m: 20 },
    });
    expect(duracao(720)).toEqual({ chave: 'MINUTOS', valores: { m: 12 } });
    expect(duracao(10)).toEqual({ chave: 'MINUTOS', valores: { m: 1 } });
    expect(duracao(64800)).toEqual({
      chave: 'SO_HORAS',
      valores: { h: 18, m: 0 },
    });
    expect(duracao(172800)).toEqual({
      chave: 'SO_DIAS',
      valores: { d: 2, h: 0 },
    });
  });

  it('shows a dash without data', () => {
    expect(duracao(Number.NaN)).toEqual({ chave: 'SEM_DADOS', valores: {} });
  });
});
