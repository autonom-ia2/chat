import {
  diaCurto,
  frase,
  ocorrencias,
  paredeDe,
  repetirVazio,
  totalDeVezes,
} from '../recorrencia';
import {
  quemRecebeDaApi,
  quemRecebeParaApi,
  recorrenciaParaApi,
  repetirDaApi,
} from '../paraApi';

const dias = (inicio, repetir, quantas = 5) =>
  ocorrencias(inicio, { ...repetirVazio(), ...repetir }, quantas).map(dia =>
    dia.toISOString().slice(0, 16)
  );
const t = (chave, vars = {}) =>
  `${chave.split('.').pop()}:${Object.values(vars).join('|')}`;
const juntar = nomes => nomes.join(' e ');

describe('recorrência dos lembretes (#1460)', () => {
  it('toda semana nos dias escolhidos, segunda primeiro', () => {
    expect(
      dias('2026-10-19T09:00', { frequencia: 'semana', dias: [3, 1] }, 4)
    ).toEqual([
      '2026-10-19T09:00',
      '2026-10-21T09:00',
      '2026-10-26T09:00',
      '2026-10-28T09:00',
    ]);
  });

  it('todo mês cai no último dia no mês curto e volta ao dia certo', () => {
    expect(dias('2027-01-31T09:00', { frequencia: 'mes' }, 3)).toEqual([
      '2027-01-31T09:00',
      '2027-02-28T09:00',
      '2027-03-31T09:00',
    ]);
  });

  it('de segunda a sexta pula o fim de semana', () => {
    expect(
      dias('2026-10-16T18:00', { frequencia: 'dia', soDiasUteis: true }, 2)
    ).toEqual(['2026-10-16T18:00', '2026-10-19T18:00']);
  });

  it('para no número de vezes e conta o total', () => {
    const repetir = {
      ...repetirVazio(),
      frequencia: 'dia',
      fim: 'vezes',
      vezes: 3,
    };
    expect(ocorrencias('2026-10-14T10:00', repetir, 10)).toHaveLength(3);
    expect(totalDeVezes('2026-10-14T10:00', repetir)).toBe(3);
  });

  it('mostra o ano só quando não é o deste ano', () => {
    const outroAno = new Date(Date.UTC(new Date().getFullYear() + 1, 0, 14));
    expect(diaCurto(outroAno, 'pt-BR')).toMatch(/\/\d{2}$/);
  });

  it('diz "Todo" para sábado e domingo e "Toda" para os outros dias', () => {
    const todo = frase({
      t,
      idioma: 'pt-BR',
      juntar,
      inicio: '2026-10-17T09:00',
      repetir: { ...repetirVazio(), frequencia: 'semana', dias: [6] },
    });
    expect(todo.startsWith('SEMANA_FIM:sábado')).toBe(true);
  });

  it('lê um instante no fuso da conta', () => {
    expect(paredeDe('2026-10-19T13:00:00Z', 'America/Sao_Paulo')).toBe(
      '2026-10-19T10:00'
    );
  });
});

describe('tradução para a API (#1460/#1462)', () => {
  it('ida e volta da repetição', () => {
    const repetir = {
      ...repetirVazio(),
      frequencia: 'semana',
      dias: [1, 3],
      fim: 'vezes',
      vezes: 6,
    };
    const api = recorrenciaParaApi(repetir, '2026-10-19T09:00');
    expect(api).toMatchObject({
      frequency: 'weekly',
      weekdays: [1, 3],
      ends_mode: 'after_count',
      occurrences_count: 6,
    });
    expect(repetirDaApi(api)).toMatchObject(repetir);
  });

  it('uma vez só não manda repetição', () => {
    expect(recorrenciaParaApi(repetirVazio(), '2026-10-19T09:00')).toBeNull();
  });

  it('ida e volta de quem recebe', () => {
    const quem = { tipo: 'pessoas', pessoas: [2, 3], time: null };
    const api = quemRecebeParaApi(quem);
    expect(api).toEqual({
      recipient_mode: 'users',
      recipient_user_ids: [2, 3],
      recipient_team_id: null,
    });
    expect(quemRecebeDaApi(api)).toEqual(quem);
  });
});
