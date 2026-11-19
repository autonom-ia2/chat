import {
  SEM_LIMITE,
  alternarDia,
  formularioDe,
  pedidoDe,
  problemaDo,
} from '../ritmo/ritmoDeEnvio';

describe('ritmoDeEnvio (#3063)', () => {
  it('starts with no limit and any hour, with sensible defaults ready', () => {
    expect(formularioDe({ limite: null, horario: null })).toEqual({
      mensagens: SEM_LIMITE,
      dias: 7,
      comHorario: false,
      inicio: 8,
      fim: 20,
      diasDaSemana: [1, 2, 3, 4, 5],
    });
  });

  it('round-trips what the server saved', () => {
    const salvo = {
      limite: { mensagens: 2, dias: 15 },
      horario: { inicio: 9, fim: 18, dias_da_semana: [1, 3, 5] },
    };

    expect(pedidoDe(formularioDe(salvo))).toEqual(salvo);
  });

  it('sends null for no limit and for any hour', () => {
    const formulario = { ...formularioDe(), comHorario: false };

    expect(pedidoDe(formulario)).toEqual({ limite: null, horario: null });
  });

  it('sorts the weekdays it sends', () => {
    const formulario = {
      ...formularioDe(),
      comHorario: true,
      diasDaSemana: [5, 0, 1],
    };

    expect(pedidoDe(formulario).horario.dias_da_semana).toEqual([0, 1, 5]);
  });

  it('flags an end before the start and a schedule with no day', () => {
    const base = { ...formularioDe(), comHorario: true };

    expect(problemaDo(base)).toBeNull();
    expect(problemaDo({ ...base, inicio: 20, fim: 8 })).toBe('FIM_ANTES');
    expect(problemaDo({ ...base, inicio: 8, fim: 8 })).toBe('FIM_ANTES');
    expect(problemaDo({ ...base, diasDaSemana: [] })).toBe('SEM_DIA');
    expect(
      problemaDo({ ...base, comHorario: false, diasDaSemana: [] })
    ).toBeNull();
  });

  it('toggles a weekday without touching the list it got', () => {
    const dias = [1, 2];

    expect(alternarDia(dias, 2)).toEqual([1]);
    expect(alternarDia(dias, 6)).toEqual([1, 2, 6]);
    expect(dias).toEqual([1, 2]);
  });
});
