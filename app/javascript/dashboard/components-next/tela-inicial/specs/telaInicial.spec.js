import { tempoDeEspera } from '../telaInicial';

describe('telaInicial', () => {
  it('mede a espera na maior unidade inteira', () => {
    expect(tempoDeEspera(0, 30)).toEqual({ unidade: 'MINUTOS', valor: 1 });
    expect(tempoDeEspera(0, 45 * 60)).toEqual({
      unidade: 'MINUTOS',
      valor: 45,
    });
    expect(tempoDeEspera(0, 3 * 3600)).toEqual({ unidade: 'HORAS', valor: 3 });
    expect(tempoDeEspera(0, 50 * 3600)).toEqual({ unidade: 'DIAS', valor: 2 });
  });
});
