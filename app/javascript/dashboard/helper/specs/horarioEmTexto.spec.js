import {
  comMaiuscula,
  diasDoCanal,
  diasDosBlocos,
  horarioEmTexto,
} from '../horarioEmTexto';
import pt from '../../i18n/locale/pt_BR/horarioDoCanal.json';

// t de verdade sobre o catálogo pt_BR: o texto final é o que a pessoa lê.
const t = (chave, params = {}) => {
  const texto = chave.split('.').reduce((nivel, parte) => nivel[parte], pt);
  return Object.entries(params).reduce(
    (atual, [nome, valor]) => atual.split(`{${nome}}`).join(valor),
    texto
  );
};

const dia = (d, abre, fecha, extra = {}) => ({
  day_of_week: d,
  closed_all_day: false,
  open_all_day: false,
  open_hour: Math.floor(abre / 60),
  open_minutes: abre % 60,
  close_hour: Math.floor(fecha / 60),
  close_minutes: fecha % 60,
  ...extra,
});

describe('horarioEmTexto (#1619)', () => {
  it('agrupa seg. a sex. do horário do canal', () => {
    const caixa = {
      working_hours_enabled: true,
      working_hours: [
        { day_of_week: 0, closed_all_day: true },
        ...[1, 2, 3, 4, 5].map(d => dia(d, 540, 1080)),
        { day_of_week: 6, closed_all_day: true },
      ],
    };
    expect(horarioEmTexto(diasDoCanal(caixa), t)).toBe(
      'seg. a sex., das 9h às 18h'
    );
  });

  it('canal com horário desligado não tem horário', () => {
    const caixa = {
      working_hours_enabled: false,
      working_hours: [dia(1, 0, 60)],
    };
    expect(horarioEmTexto(diasDoCanal(caixa), t)).toBeNull();
  });

  it('todos os dias, o dia todo', () => {
    const caixa = {
      working_hours_enabled: true,
      working_hours: [0, 1, 2, 3, 4, 5, 6].map(d =>
        dia(d, 0, 1439, { open_all_day: true })
      ),
    };
    expect(horarioEmTexto(diasDoCanal(caixa), t)).toBe(
      'todos os dias, o dia todo'
    );
  });

  it('calendário da pessoa com almoço e minutos', () => {
    const blocos = [1, 2, 3, 4, 5].flatMap(d => [
      { day_of_week: d, start_minute: 780, end_minute: 1080 },
      { day_of_week: d, start_minute: 540, end_minute: 720 },
    ]);
    blocos.push({ day_of_week: 6, start_minute: 570, end_minute: 750 });
    expect(comMaiuscula(horarioEmTexto(diasDosBlocos(blocos), t))).toBe(
      'Seg. a sex., das 9h às 12h e das 13h às 18h; sáb., das 9h30 às 12h30'
    );
  });

  it('dias soltos aparecem um a um', () => {
    const blocos = [1, 3].map(d => ({
      day_of_week: d,
      start_minute: 0,
      end_minute: 1440,
    }));
    expect(horarioEmTexto(diasDosBlocos(blocos), t)).toBe(
      'seg., qua., o dia todo'
    );
  });

  it('sem blocos não tem horário', () => {
    expect(horarioEmTexto(diasDosBlocos([]), t)).toBeNull();
  });
});
