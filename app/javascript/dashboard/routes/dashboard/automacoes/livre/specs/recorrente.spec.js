import { faltaDaFrequencia, mostraNaFrequencia } from '../recorrente';

describe('recorrente: o que cada frequência pede', () => {
  it('o dia da semana só no semanal, o do mês só no mensal, a data só no "uma vez"', () => {
    expect(mostraNaFrequencia('dia_da_semana', 'semanal')).toBe(true);
    expect(mostraNaFrequencia('dia_da_semana', 'mensal')).toBe(false);
    expect(mostraNaFrequencia('dia_do_mes', 'mensal')).toBe(true);
    expect(mostraNaFrequencia('data', 'uma_vez')).toBe(true);
    expect(mostraNaFrequencia('data', 'diaria')).toBe(false);
    expect(mostraNaFrequencia('hora', 'diaria')).toBe(true);
  });

  // G39: sem a data, o "uma vez" não salva (antes, o servidor recusava com uma
  // frase técnica); vale também para o dia do semanal e do mensal.
  it('falta o que a frequência escolhida pede; domingo (0) não falta', () => {
    expect(faltaDaFrequencia({ frequencia: 'uma_vez', hora: 9 })).toBe(true);
    expect(faltaDaFrequencia({ frequencia: 'uma_vez', data: '' })).toBe(true);
    expect(
      faltaDaFrequencia({ frequencia: 'uma_vez', data: '2026-11-26' })
    ).toBe(false);
    expect(faltaDaFrequencia({ frequencia: 'semanal' })).toBe(true);
    expect(faltaDaFrequencia({ frequencia: 'semanal', dia_da_semana: 0 })).toBe(
      false
    );
    expect(faltaDaFrequencia({ frequencia: 'mensal' })).toBe(true);
    expect(faltaDaFrequencia({ frequencia: 'diaria' })).toBe(false);
    expect(faltaDaFrequencia({ tipo: 'conversa.resolvida' })).toBe(false);
  });
});
