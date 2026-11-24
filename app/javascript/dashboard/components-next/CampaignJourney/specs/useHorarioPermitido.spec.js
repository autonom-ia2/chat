import { diasEmTexto, horarioEmTexto } from '../ritmo/useHorarioPermitido';

// #3101: o horário de envio da conta em palavras, para o melhor horário dizer que respeita ele.
const t = (chave, valores) =>
  valores
    ? `${chave.split('.').pop()}(${Object.values(valores).join('|')})`
    : chave.split('.').pop();

describe('horário permitido em palavras (#3101)', () => {
  it('diz de segunda a sexta, todos os dias ou a lista dos dias', () => {
    expect(diasEmTexto([1, 2, 3, 4, 5], t, 'pt_BR')).toBe('UTEIS');
    expect(diasEmTexto([0, 1, 2, 3, 4, 5, 6], t, 'pt_BR')).toBe('TODOS');
    expect(diasEmTexto([5, 1], t, 'pt_BR')).toBe('1 e 5');
  });

  it('junta os dias e as horas; sem horário, vazio (a qualquer hora)', () => {
    const horario = { inicio: 8, fim: 20, dias_da_semana: [1, 2, 3, 4, 5] };

    expect(horarioEmTexto(horario, t, 'pt_BR')).toBe(
      'HORARIO_PERMITIDO(UTEIS|HORA(8)|HORA(20))'
    );
    expect(horarioEmTexto(null, t, 'pt_BR')).toBe('');
  });
});
