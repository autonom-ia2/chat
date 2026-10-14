import {
  chaveDoDia,
  minutosDoDia,
  somarDias,
  diasEntre,
  inicioDaSemana,
  semanasDoMes,
  somarMeses,
  instanteNaConta,
} from './tempoNaConta';

describe('tempoNaConta', () => {
  it('dá o dia e a hora no fuso da conta, não no do navegador', () => {
    const instante = new Date('2026-10-15T01:30:00Z');
    expect(chaveDoDia(instante, 'America/Sao_Paulo')).toBe('2026-10-14');
    expect(chaveDoDia(instante, 'Europe/Lisbon')).toBe('2026-10-15');
    expect(minutosDoDia(instante, 'America/Sao_Paulo')).toBe(22 * 60 + 30);
  });

  it('soma dias e meses sobre a chave, virando mês e ano', () => {
    expect(somarDias('2026-10-31', 1)).toBe('2026-11-01');
    expect(somarDias('2026-01-01', -1)).toBe('2025-12-31');
    expect(diasEntre('2026-10-12', '2026-10-14')).toBe(2);
    expect(somarMeses('2026-12-20', 1)).toBe('2027-01-01');
  });

  it('a semana começa no domingo e o mês cobre semanas inteiras', () => {
    expect(inicioDaSemana('2026-10-14')).toBe('2026-10-11');
    const semanas = semanasDoMes('2026-10-14');
    expect(semanas[0][0]).toBe('2026-09-27');
    expect(semanas.at(-1)[6]).toBe('2026-10-31');
    expect(semanas.every(semana => semana.length === 7)).toBe(true);
  });

  it('converte dia e hora da conta em instante UTC', () => {
    expect(instanteNaConta('2026-10-15', '09:00', 'America/Sao_Paulo')).toBe(
      '2026-10-15T12:00:00.000Z'
    );
  });
});
