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
// Quinta, 23/10/2026, 22h30 em São Paulo (sexta 01h30 em UTC).
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
