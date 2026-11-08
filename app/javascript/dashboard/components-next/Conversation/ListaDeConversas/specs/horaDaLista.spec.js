import { horaDaLista, horaComDia } from '../horaDaLista';
import { FUSO, emSaoPaulo, t } from './apoio';

// Domingo, 25/10/2026, 19:21 em São Paulo.
const agora = emSaoPaulo(2026, 10, 25, 19, 21);
const hora = quando => horaDaLista({ quando, agora, fuso: FUSO, t });

describe('horaDaLista (#2202, linha 1)', () => {
  it('hoje: a hora, como no WhatsApp', () => {
    expect(hora(emSaoPaulo(2026, 10, 25, 17, 21))).toBe('17:21');
    expect(hora(emSaoPaulo(2026, 10, 25, 0, 5))).toBe('00:05');
  });

  it('a virada do dia é no fuso da conta, não no do navegador (UTC)', () => {
    // 23:30 de sábado em São Paulo já é domingo em UTC: continua "Ontem".
    expect(hora(emSaoPaulo(2026, 10, 24, 23, 30))).toBe('Ontem');
  });

  it('de 2 a 6 dias: o dia da semana curto; o 7º dia já é data', () => {
    expect(hora(emSaoPaulo(2026, 10, 23, 10))).toBe('sex');
    expect(hora(emSaoPaulo(2026, 10, 19, 10))).toBe('seg');
    expect(hora(emSaoPaulo(2026, 10, 18, 10))).toBe('18/10');
  });

  it('outro ano: com o ano', () => {
    expect(hora(emSaoPaulo(2025, 12, 31, 10))).toBe('31/12/2025');
  });

  it('virada de ano: 1º de janeiro vê 31/12 como "Ontem"', () => {
    const ano = emSaoPaulo(2027, 1, 1, 9);
    expect(
      horaDaLista({
        quando: emSaoPaulo(2026, 12, 31, 22),
        agora: ano,
        fuso: FUSO,
        t,
      })
    ).toBe('Ontem');
  });
});

describe('horaComDia (#2202, "Adiada até")', () => {
  const ate = quando => horaComDia({ quando, agora, fuso: FUSO, t });

  it('hoje, amanhã, dia da semana e data, com a hora sem zero', () => {
    expect(ate(emSaoPaulo(2026, 10, 25, 21))).toBe('hoje 21:00');
    expect(ate(emSaoPaulo(2026, 10, 26, 9))).toBe('amanhã 9:00');
    expect(ate(emSaoPaulo(2026, 10, 27, 9))).toBe('ter 9:00');
    expect(ate(emSaoPaulo(2026, 11, 12, 9))).toBe('12/11 9:00');
  });
});
