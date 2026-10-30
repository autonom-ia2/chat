import { diaFalado, horaFalada } from '../dataFalada';

const nomes = {
  hoje: 'hoje',
  amanha: 'amanhã',
  ontem: 'ontem',
  semana: [
    'domingo',
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
  ],
};
const fuso = 'America/Sao_Paulo';
// Sexta, 23/10/2026, 22h30 em São Paulo (sábado 01h30 em UTC).
const agora = new Date('2026-10-24T01:30:00Z');
const falar = iso => diaFalado({ quando: new Date(iso), agora, fuso, nomes });

describe('diaFalado', () => {
  it('compara o dia no fuso da conta, não no UTC', () => {
    expect(falar('2026-10-23T13:00:00Z')).toBe('hoje');
    expect(falar('2026-10-24T13:00:00Z')).toBe('amanhã');
    expect(falar('2026-10-22T13:00:00Z')).toBe('ontem');
  });

  it('usa o dia da semana até 6 dias e depois dia e mês', () => {
    expect(falar('2026-10-20T13:00:00Z')).toBe('terça');
    expect(falar('2026-10-29T13:00:00Z')).toBe('quinta');
    expect(falar('2026-11-25T13:00:00Z')).toBe('25 de novembro');
    expect(falar('2027-11-25T13:00:00Z')).toBe('25 de novembro de 2027');
  });
});

describe('horaFalada', () => {
  it('fala a hora cheia e a quebrada', () => {
    expect(horaFalada(new Date('2026-10-23T13:00:00Z'), fuso)).toBe('10h');
    expect(horaFalada(new Date('2026-10-23T12:30:00Z'), fuso)).toBe('9h30');
  });
});

// A virada do dia: o navegador em UTC (TZ=UTC no vitest) e a conta em São Paulo.
// Pelo relógio do navegador, os dois momentos de cada caso caem no mesmo dia; no
// fuso da conta, não.
describe('diaFalado na virada da meia-noite', () => {
  it('roda com o navegador em UTC', () => {
    expect(new Date('2026-10-24T03:00:00Z').getTimezoneOffset()).toBe(0);
  });

  it('23h59 em São Paulo: 0h30 de lá é amanhã, mesmo sendo o mesmo dia em UTC', () => {
    const quase = new Date('2026-10-24T02:59:00Z'); // 23/10, 23h59 em SP
    const depois = new Date('2026-10-24T03:30:00Z'); // 24/10, 0h30 em SP
    expect(diaFalado({ quando: depois, agora: quase, fuso, nomes })).toBe(
      'amanhã'
    );
    expect(horaFalada(depois, fuso)).toBe('0h30');
  });

  it('0h01 em São Paulo: 23h30 de lá é ontem, mesmo sendo o mesmo dia em UTC', () => {
    const agoraCedo = new Date('2026-10-24T03:01:00Z'); // 24/10, 0h01 em SP
    const antes = new Date('2026-10-24T02:30:00Z'); // 23/10, 23h30 em SP
    expect(diaFalado({ quando: antes, agora: agoraCedo, fuso, nomes })).toBe(
      'ontem'
    );
  });

  it('hoje vale até 23h59 do fuso da conta', () => {
    const cedo = new Date('2026-10-23T03:00:00Z'); // 23/10, 0h em SP
    const tarde = new Date('2026-10-24T02:59:00Z'); // 23/10, 23h59 em SP
    expect(diaFalado({ quando: tarde, agora: cedo, fuso, nomes })).toBe('hoje');
  });
});
